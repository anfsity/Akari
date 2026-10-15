mod kms;
mod renderer;
mod timing;
mod window;

use std::{env, error::Error, path::PathBuf, sync::Arc, sync::atomic::AtomicBool, time::Duration};

type Result<T = ()> = std::result::Result<T, Box<dyn Error>>;

#[derive(Clone, Copy)]
enum Target {
    Window,
    Kms,
    Clear,
}

struct Options {
    target: Target,
    duration: Duration,
    dark: bool,
    snapshot: Option<PathBuf>,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("Akari splash: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result {
    let arguments: Vec<_> = env::args().skip(1).collect();
    if arguments.iter().any(|argument| argument == "--help") {
        println!(
            "Usage: akari-splash window|kms [--duration SECONDS] [--dark|--light] [--snapshot PNG]\n\
                  akari-splash clear\n\
                  Defaults: dark background, 3 seconds minimum; 0 skips the hold.\n\
                  AKARI_SPLASH_DURATION also sets the minimum display time."
        );
        return Ok(());
    }
    let options = Options::parse(arguments, env::var("AKARI_SPLASH_DURATION").ok())?;
    let stop = Arc::new(AtomicBool::new(false));
    for signal in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP, libc::SIGQUIT] {
        signal_hook::flag::register(signal, Arc::clone(&stop))?;
    }
    let parent = env::var("AKARI_SPLASH_PARENT_PID")
        .ok()
        .map(|value| value.parse::<libc::pid_t>())
        .transpose()?
        .unwrap_or_else(|| unsafe { libc::getppid() });
    // The launcher's PID closes the fork/exec race: an already orphaned child
    // must also exit. No detached animator survives its owning launcher.
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    if unsafe { libc::getppid() } != parent {
        return Ok(());
    }
    match options.target {
        Target::Window => window::run(options, renderer::Renderer::load()?, stop),
        Target::Kms => kms::run(options, renderer::Renderer::load()?, stop),
        Target::Clear => kms::clear_terminal(),
    }
}

impl Options {
    fn parse(arguments: Vec<String>, environment_duration: Option<String>) -> Result<Self> {
        let mut arguments = arguments.into_iter();
        let target = match arguments.next().as_deref() {
            Some("window") => Target::Window,
            Some("kms") => Target::Kms,
            Some("clear") => Target::Clear,
            _ => return Err("expected window, kms or clear (see --help)".into()),
        };
        if matches!(target, Target::Clear) {
            if arguments.len() != 0 {
                return Err("clear does not accept options".into());
            }
            return Ok(Self {
                target,
                duration: Duration::ZERO,
                dark: false,
                snapshot: None,
            });
        }
        let mut duration = environment_duration.unwrap_or_else(|| "3".to_owned());
        let mut dark = true;
        let mut snapshot = None;
        while let Some(argument) = arguments.next() {
            match argument.as_str() {
                "--duration" => duration = arguments.next().ok_or("missing duration")?,
                "--dark" => dark = true,
                "--light" => dark = false,
                "--snapshot" => snapshot = Some(arguments.next().ok_or("missing PNG path")?.into()),
                _ => return Err(format!("unknown option: {argument}").into()),
            }
        }
        let duration = Duration::try_from_secs_f64(duration.parse()?)
            .map_err(|_| "duration must be a finite, non-negative number of seconds")?;
        Ok(Self {
            target,
            duration,
            dark,
            snapshot,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_duration_at_the_process_boundary() {
        for value in ["-1", "NaN", "inf", "1e300", "invalid"] {
            assert!(
                Options::parse(
                    vec!["window".into(), "--duration".into(), value.into()],
                    None
                )
                .is_err()
            );
        }
        for value in ["0", "1.2", "3"] {
            let options = Options::parse(
                vec!["window".into(), "--duration".into(), value.into()],
                None,
            )
            .unwrap();
            assert_eq!(
                options.duration.as_secs_f64(),
                value.parse::<f64>().unwrap()
            );
        }
        assert_eq!(
            Options::parse(vec!["kms".into()], None).unwrap().duration,
            Duration::from_secs(3)
        );
        assert_eq!(
            Options::parse(vec!["kms".into()], Some("3".into()))
                .unwrap()
                .duration,
            Duration::from_secs(3)
        );
    }

    #[test]
    fn defaults_to_dark_with_an_explicit_light_override() {
        for target in ["window", "kms"] {
            assert!(Options::parse(vec![target.into()], None).unwrap().dark);
            assert!(
                !Options::parse(vec![target.into(), "--light".into()], None)
                    .unwrap()
                    .dark
            );
        }
    }
}
