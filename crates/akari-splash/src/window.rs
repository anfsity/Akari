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
        pending_redraw: false,
        error: None,
    };
    event_loop.run_app(&mut app)?;
    // Destruction closes the surface before returning control to the launcher.
    app.close();
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
    pending_redraw: bool,
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
        self.pending_redraw = false;
        Ok(())
    }

    fn close(&mut self) {
        self.pending_redraw = false;
        self.surface.take();
        self.window.take();
    }

    fn present(&mut self) -> Result {
        self.next_frame = Instant::now() + Duration::from_millis(33);
        let Some(window) = self.window.as_ref() else {
            return Ok(());
        };
        let size = window.inner_size();
        let (Some(width), Some(height)) =
            (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
        else {
            return Ok(());
        };
        if self
            .scene
            .as_ref()
            .is_none_or(|scene| !scene.has_size(size.width, size.height))
        {
            self.scene = Some(self.renderer.create_scene(
                size.width,
                size.height,
                self.options.dark,
            )?);
        }
        let (Some(surface), Some(scene)) = (self.surface.as_mut(), self.scene.as_mut()) else {
            return Ok(());
        };
        surface.resize(width, height)?;
        scene.draw(self.timing.get_elapsed(Instant::now()).as_secs_f32());
        if let Some(path) = self.options.snapshot.take() {
            scene.save_png(path)?;
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
                self.pending_redraw = false;
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
        let now = Instant::now();
        if self.stop.load(Ordering::Relaxed) || self.timing.is_finished(now) {
            event_loop.exit();
            return;
        }
        match plan_frame_wait(self.window.is_some(), self.pending_redraw, now, self.next_frame) {
            FrameWaitPlan::Wait => event_loop.set_control_flow(ControlFlow::Wait),
            FrameWaitPlan::RequestRedrawAndWait => {
                if let Some(window) = self.window.as_ref() {
                    self.pending_redraw = true;
                    window.request_redraw();
                }
                event_loop.set_control_flow(ControlFlow::Wait);
            }
            FrameWaitPlan::WaitUntil(deadline) => {
                event_loop.set_control_flow(ControlFlow::WaitUntil(deadline));
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FrameWaitPlan {
    Wait,
    RequestRedrawAndWait,
    WaitUntil(Instant),
}

fn plan_frame_wait(
    has_window: bool,
    pending_redraw: bool,
    now: Instant,
    next_frame: Instant,
) -> FrameWaitPlan {
    if !has_window || pending_redraw {
        return FrameWaitPlan::Wait;
    }
    if now >= next_frame {
        return FrameWaitPlan::RequestRedrawAndWait;
    }
    FrameWaitPlan::WaitUntil(next_frame)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_wait_avoids_busy_spinning_without_window_or_with_pending_redraw() {
        let now = Instant::now();
        let past = now - Duration::from_millis(5);
        assert_eq!(plan_frame_wait(false, false, now, past), FrameWaitPlan::Wait);
        assert_eq!(plan_frame_wait(true, true, now, past), FrameWaitPlan::Wait);
        assert_eq!(
            plan_frame_wait(true, false, now, past),
            FrameWaitPlan::RequestRedrawAndWait
        );
        let future = now + Duration::from_millis(33);
        assert_eq!(
            plan_frame_wait(true, false, now, future),
            FrameWaitPlan::WaitUntil(future)
        );
    }
}
