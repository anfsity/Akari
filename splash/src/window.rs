use std::{
    num::NonZeroU32,
    rc::Rc,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use softbuffer::{Context, Surface};
use winit::{
    application::ApplicationHandler,
    dpi::LogicalSize,
    event::WindowEvent,
    event_loop::{ActiveEventLoop, ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    platform::wayland::WindowAttributesExtWayland,
    window::{Window, WindowId},
};

use crate::{
    Options, Result,
    renderer::{Renderer, Scene},
    timing::Presentation,
};

pub fn run(options: Options, renderer: Renderer, stop: Arc<AtomicBool>) -> Result {
    let event_loop = EventLoop::new()?;
    let mut app = Preview {
        timing: Presentation::new(options.duration),
        options,
        renderer,
        stop,
        window: None,
        surface: None,
        scene: None,
        next_frame: Instant::now(),
        error: None,
    };
    event_loop.run_app(&mut app)?;
    // Destruction closes the surface before returning control to the launcher.
    app.surface.take();
    app.window.take();
    app.error.map_or(Ok(()), Err)
}

struct Preview {
    options: Options,
    renderer: Renderer,
    timing: Presentation,
    stop: Arc<AtomicBool>,
    window: Option<Rc<Window>>,
    surface: Option<Surface<Rc<Window>, Rc<Window>>>,
    scene: Option<Scene>,
    next_frame: Instant,
    error: Option<Box<dyn std::error::Error>>,
}

impl Preview {
    fn open(&mut self, event_loop: &ActiveEventLoop) -> Result {
        let attributes = Window::default_attributes()
            .with_title("Akari · Starting")
            .with_name("io.akari.Splash", "akari-splash")
            .with_inner_size(LogicalSize::new(1128, 760));
        let window = Rc::new(event_loop.create_window(attributes)?);
        let context = Context::new(Rc::clone(&window))?;
        self.surface = Some(Surface::new(&context, Rc::clone(&window))?);
        self.window = Some(window);
        Ok(())
    }

    fn present(&mut self) -> Result {
        self.next_frame = Instant::now() + Duration::from_millis(33);
        let window = self.window.as_ref().unwrap();
        let size = window.inner_size();
        let (Some(width), Some(height)) =
            (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
        else {
            return Ok(());
        };
        if self.scene.as_ref().is_none_or(|scene| {
            scene.pixels.width() != size.width || scene.pixels.height() != size.height
        }) {
            self.scene = Some(self.renderer.create_scene(
                size.width,
                size.height,
                self.options.dark,
            )?);
        }
        let surface = self.surface.as_mut().unwrap();
        surface.resize(width, height)?;
        let scene = self.scene.as_mut().unwrap();
        scene.draw(self.timing.get_elapsed(Instant::now()).as_secs_f32());
        if let Some(path) = self.options.snapshot.take() {
            scene.pixels.save_png(path)?;
        }
        let mut buffer = surface.buffer_mut()?;
        scene.copy_xrgb(&mut buffer);
        window.pre_present_notify();
        buffer.present()?;
        self.timing.mark_presented(Instant::now());
        Ok(())
    }
}

impl ApplicationHandler for Preview {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if let Err(error) = self.open(event_loop) {
            self.error = Some(error);
            event_loop.exit();
        }
    }

    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        event_loop.exit();
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::KeyboardInput { event, .. }
                if event.logical_key == Key::Named(NamedKey::Escape)
                    && event.state.is_pressed() =>
            {
                event_loop.exit()
            }
            WindowEvent::RedrawRequested => {
                if let Err(error) = self.present() {
                    self.error = Some(error);
                    event_loop.exit();
                }
                if self.timing.is_finished(Instant::now()) {
                    event_loop.exit();
                }
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if self.stop.load(Ordering::Relaxed) || self.timing.is_finished(Instant::now()) {
            event_loop.exit();
            return;
        }
        if Instant::now() >= self.next_frame {
            self.window.as_ref().unwrap().request_redraw();
        }
        event_loop.set_control_flow(ControlFlow::WaitUntil(self.next_frame));
    }
}
