use std::{
    cell::{Cell, RefCell},
    collections::HashSet,
    fs::{File, OpenOptions},
    io::{self, Write},
    os::fd::{AsFd, AsRawFd, BorrowedFd, FromRawFd, OwnedFd},
    path::PathBuf,
    rc::Rc,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use drm::{
    Device as _,
    buffer::{Buffer, DrmFourcc},
    control::{
        Device as _, Mode, ModeTypeFlags, connector, crtc, dumbbuffer::DumbBuffer, framebuffer,
    },
};
use libseat::{Device, Seat, SeatEvent, SeatRef};

use crate::{
    Options, Result,
    renderer::{Renderer, Scene},
    timing::Presentation,
};

const KDGETMODE: libc::Ioctl = 0x4b3b;
const KDSETMODE: libc::Ioctl = 0x4b3a;
const KD_TEXT: libc::c_int = 0;
const KD_GRAPHICS: libc::c_int = 1;
const CLEAR: &[u8] = b"\x1b[0m\x1b[2J\x1b[3J\x1b[H\x1b[?25h";

pub fn clear_terminal() -> Result {
    let mut terminal = open_terminal()?;
    terminal.write_all(CLEAR)?;
    Ok(())
}

fn open_terminal() -> io::Result<File> {
    let terminal = OpenOptions::new().read(true).write(true).open("/dev/tty")?;
    let mut mode: libc::c_int = 0;
    // KDGETMODE is supported by real Linux VTs, but not desktop PTYs.
    if unsafe { libc::ioctl(terminal.as_raw_fd(), KDGETMODE, &mut mode) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(terminal)
}

struct Terminal(File);

impl Terminal {
    fn enter_graphics() -> Result<Self> {
        let mut terminal = open_terminal()?;
        terminal.write_all(CLEAR)?;
        if unsafe { libc::ioctl(terminal.as_raw_fd(), KDSETMODE, KD_GRAPHICS) } < 0 {
            return Err(io::Error::last_os_error().into());
        }
        Ok(Self(terminal))
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        // This runs while the seat still belongs to us. It erases the hidden
        // text buffer as well, so desktop exit cannot uncover startup output.
        let _ = self.0.write_all(CLEAR);
        unsafe {
            libc::ioctl(self.0.as_raw_fd(), KDSETMODE, KD_TEXT);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Activation {
    Waiting,
    Enabled,
    Released,
}

/// A disable notification is terminal for this short-lived renderer. All
/// drawing and cleanup finish before acknowledging it; a later enable cannot
/// repaint the old screen or restore an earlier compositor's CRTC state.
struct Display {
    terminal: Option<Terminal>,
    cards: Vec<Card>,
}

impl Display {
    fn close(&mut self, seat: &mut SeatRef) {
        self.terminal.take();
        for card in self.cards.drain(..) {
            card.close(seat);
        }
    }
}

struct Session {
    seat: Seat,
    display: Rc<RefCell<Display>>,
    activation: Rc<Cell<Activation>>,
}

impl Session {
    fn open() -> Result<Self> {
        // Reject PTYs before contacting the seat manager. Preview must never
        // acquire DRM devices or change the active desktop's terminal mode.
        open_terminal()?;
        let display = Rc::new(RefCell::new(Display {
            terminal: None,
            cards: Vec::new(),
        }));
        let activation = Rc::new(Cell::new(Activation::Waiting));
        let state = Rc::clone(&activation);
        let devices = Rc::clone(&display);
        let seat = Seat::open(move |seat, event| match event {
            SeatEvent::Enable if state.get() == Activation::Waiting => {
                state.set(Activation::Enabled)
            }
            SeatEvent::Enable => {}
            SeatEvent::Disable => {
                state.set(Activation::Released);
                devices.borrow_mut().close(seat);
                if let Err(error) = seat.disable() {
                    eprintln!("event=splash_disable_failed error={error}");
                }
            }
        })?;
        Ok(Self {
            seat,
            display,
            activation,
        })
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.display.borrow_mut().close(&mut self.seat);
        self.activation.set(Activation::Released);
        // Seat::drop releases session control before the process exits.
    }
}

pub fn run(mut options: Options, renderer: Renderer, stop: Arc<AtomicBool>) -> Result {
    let mut session = Session::open()?;
    let activation_deadline = Instant::now() + Duration::from_secs(3);
    while session.activation.get() == Activation::Waiting && !stop.load(Ordering::Relaxed) {
        if Instant::now() >= activation_deadline {
            return Err("seat activation timed out".into());
        }
        session.seat.dispatch(20)?;
    }
    if session.activation.get() != Activation::Enabled || stop.load(Ordering::Relaxed) {
        return Ok(());
    }
    session.display.borrow_mut().terminal = Some(Terminal::enter_graphics()?);
    for path in get_card_paths()? {
        session.seat.dispatch(0)?;
        if session.activation.get() != Activation::Enabled {
            return Ok(());
        }
        match session.seat.open_device(&path) {
            Ok(device) => {
                let mut display = session.display.borrow_mut();
                display.cards.push(Card {
                    device: CardDevice {
                        fd: unsafe { OwnedFd::from_raw_fd(device.as_fd().as_raw_fd()) },
                        seat_device: device,
                    },
                    outputs: Vec::new(),
                });
                if let Err(error) = display
                    .cards
                    .last_mut()
                    .unwrap()
                    .create_outputs(&renderer, options.dark)
                {
                    eprintln!("event=splash_card_unavailable path={path:?} error={error}");
                }
            }
            Err(error) => eprintln!("event=splash_card_unavailable path={path:?} error={error}"),
        }
    }
    if session
        .display
        .borrow()
        .cards
        .iter()
        .all(|card| card.outputs.is_empty())
    {
        return Err("no usable DRM outputs on the current seat".into());
    }
    let mut timing = Presentation::new(options.duration);
    loop {
        session.seat.dispatch(0)?;
        if session.activation.get() != Activation::Enabled
            || stop.load(Ordering::Relaxed)
            || timing.is_finished(Instant::now())
        {
            break;
        }
        let mut display = session.display.borrow_mut();
        for card in &mut display.cards {
            card.present(&mut timing, &mut options.snapshot)?;
        }
        drop(display);
        // Dispatch instead of sleeping so VT revocation is acknowledged promptly.
        session.seat.dispatch(33)?;
    }
    drop(session);
    eprintln!("event=splash_released");
    Ok(())
}

fn get_card_paths() -> io::Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    for entry in std::fs::read_dir("/dev/dri")? {
        let entry = entry?;
        if entry
            .file_name()
            .to_str()
            .and_then(|name| name.strip_prefix("card"))
            .is_some_and(|index| {
                !index.is_empty() && index.bytes().all(|byte| byte.is_ascii_digit())
            })
        {
            paths.push(entry.path());
        }
    }
    paths.sort();
    Ok(paths)
}

struct Card {
    device: CardDevice,
    outputs: Vec<Output>,
}
// libseat tracks access to the device but leaves closing the returned FD to
// its caller. Keeping both owners explicit avoids leaking DRM master at exit.
struct CardDevice {
    seat_device: Device,
    fd: OwnedFd,
}
impl AsFd for CardDevice {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.fd.as_fd()
    }
}
impl drm::Device for CardDevice {}
impl drm::control::Device for CardDevice {}

struct Output {
    crtc: crtc::Handle,
    connectors: Vec<connector::Handle>,
    mode: Mode,
    buffer: DumbBuffer,
    framebuffer: framebuffer::Handle,
    scene: Scene,
    presented: bool,
    flush_damage: bool,
}

impl Card {
    fn create_outputs(&mut self, renderer: &Renderer, dark: bool) -> Result {
        let card = &self.device;
        let resources = card.resource_handles()?;
        let mut used = HashSet::new();
        let mut connectors = resources
            .connectors()
            .iter()
            .map(|handle| {
                let connector = card.get_connector(*handle, true)?;
                let current = connector
                    .current_encoder()
                    .map(|encoder| card.get_encoder(encoder))
                    .transpose()?
                    .and_then(|encoder| encoder.crtc());
                Ok((connector, current))
            })
            .collect::<io::Result<Vec<_>>>()?;
        // Reserve active CRTCs first. New outputs must not steal one from an
        // already lit connector; cloned connectors share that CRTC's buffer.
        connectors.sort_by_key(|(_, current)| current.is_none());
        for (connector, current) in connectors {
            if connector.state() != connector::State::Connected {
                continue;
            }
            if let Some(output) =
                current.and_then(|crtc| self.outputs.iter_mut().find(|output| output.crtc == crtc))
            {
                output.connectors.push(connector.handle());
                continue;
            }
            let crtc = current.or_else(|| {
                connector
                    .encoders()
                    .iter()
                    .filter_map(|encoder| card.get_encoder(*encoder).ok())
                    .flat_map(|encoder| resources.filter_crtcs(encoder.possible_crtcs()))
                    .find(|crtc| !used.contains(crtc))
            });
            let Some(crtc) = crtc else {
                continue;
            };
            let current_mode = card.get_crtc(crtc)?.mode();
            let mode = current_mode
                .or_else(|| {
                    connector
                        .modes()
                        .iter()
                        .find(|mode| mode.mode_type().contains(ModeTypeFlags::PREFERRED))
                        .copied()
                })
                .or_else(|| connector.modes().first().copied());
            let Some(mode) = mode else {
                continue;
            };
            let size = (u32::from(mode.size().0), u32::from(mode.size().1));
            let scene = renderer.create_scene(size.0, size.1, dark)?;
            let buffer = card.create_dumb_buffer(size, DrmFourcc::Xrgb8888, 32)?;
            let framebuffer = match card.add_framebuffer(&buffer, 24, 32) {
                Ok(framebuffer) => framebuffer,
                Err(error) => {
                    card.destroy_dumb_buffer(buffer)?;
                    return Err(error.into());
                }
            };
            self.outputs.push(Output {
                crtc,
                connectors: vec![connector.handle()],
                mode,
                buffer,
                framebuffer,
                scene,
                presented: false,
                flush_damage: true,
            });
            used.insert(crtc);
        }
        Ok(())
    }

    fn present(&mut self, timing: &mut Presentation, snapshot: &mut Option<PathBuf>) -> Result {
        let card = &self.device;
        for output in &mut self.outputs {
            output
                .scene
                .draw(timing.get_elapsed(Instant::now()).as_secs_f32());
            let pitch = output.buffer.pitch() as usize;
            {
                let mut mapping = card.map_dumb_buffer(&mut output.buffer)?;
                for (source, target) in output
                    .scene
                    .pixels
                    .data()
                    .chunks_exact(output.scene.pixels.width() as usize * 4)
                    .zip(mapping.chunks_mut(pitch))
                {
                    for (rgba, pixel) in source
                        .as_chunks::<4>()
                        .0
                        .iter()
                        .zip(target.as_chunks_mut::<4>().0)
                    {
                        pixel.copy_from_slice(&[rgba[2], rgba[1], rgba[0], 0]);
                    }
                }
            }
            // Shadow framebuffers need damage notification to upload CPU
            // writes. Native scanout drivers can report this as unsupported.
            if output.flush_damage {
                match card.dirty_framebuffer(output.framebuffer, &[]) {
                    Ok(()) => {}
                    Err(error) if error.raw_os_error() == Some(libc::ENOSYS) => {
                        output.flush_damage = false;
                    }
                    Err(error) => return Err(error.into()),
                }
            }
            if !output.presented {
                card.set_crtc(
                    output.crtc,
                    Some(output.framebuffer),
                    (0, 0),
                    &output.connectors,
                    Some(output.mode),
                )?;
                output.presented = true;
                timing.mark_presented(Instant::now());
                eprintln!(
                    "event=splash_presented connectors={:?} resolution={:?}",
                    output.connectors,
                    output.mode.size()
                );
            }
            if let Some(path) = snapshot.take() {
                output.scene.pixels.save_png(path)?;
            }
        }
        Ok(())
    }

    fn close(self, seat: &mut SeatRef) {
        let card = &self.device;
        // CLOSEFB drops userspace ownership without disabling active scanout.
        // Older kernels can only RMFB; those cannot retain the last frame.
        // Neither path restores the compositor state saved before this process.
        for output in &self.outputs {
            #[repr(C)]
            struct CloseFramebuffer {
                fb_id: u32,
                pad: u32,
            }
            let mut close = CloseFramebuffer {
                fb_id: output.framebuffer.into(),
                pad: 0,
            };
            let result = unsafe {
                libc::ioctl(
                    card.as_fd().as_raw_fd(),
                    libc::_IOWR::<CloseFramebuffer>(b'd'.into(), 0xd0),
                    &mut close,
                )
            };
            if result < 0 {
                let _ = card.destroy_framebuffer(output.framebuffer);
            }
            let _ = card.destroy_dumb_buffer(output.buffer);
        }
        let _ = card.release_master_lock();
        if let Err(error) = seat.close_device(self.device.seat_device) {
            eprintln!("event=splash_close_device_failed error={error}");
        }
    }
}
