mod kms;
mod renderer;
mod timing;
mod window;

use std::{env, error::Error, path::PathBuf, sync::Arc, sync::atomic::AtomicBool, time::Duration};

type Result<T = ()> = std::result::Result<T, Box<dyn Error>>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Target {
    Window,
    Kms,
}

enum Command {
    Present(Options),
    Clear,
}

struct Options {
    target: Target,
    duration: Option<Duration>,
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
                  akari-splash window --hold [--dark|--light] [--snapshot PNG]\n\
                  akari-splash clear\n\
                  Defaults: black background, 3 seconds minimum; 0 skips the hold.\n\
                  --hold keeps the window open until closed or interrupted.\n\
                  AKARI_SPLASH_DURATION also sets the minimum display time."
        );
        return Ok(());
    }
    match Command::parse(arguments, env::var("AKARI_SPLASH_DURATION").ok())? {
        Command::Clear => kms::clear_terminal(),
        Command::Present(options) => present_splash(options),
    }
}

fn present_splash(options: Options) -> Result {
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
    let renderer = renderer::Renderer::load()?;
    match options.target {
        Target::Window => window::run(options, renderer, stop),
        Target::Kms => kms::run(options, renderer, stop),
    }
}

impl Command {
    fn parse(arguments: Vec<String>, environment_duration: Option<String>) -> Result<Self> {
        let mut arguments = arguments.into_iter();
        let target = match arguments.next().as_deref() {
            Some("window") => Target::Window,
            Some("kms") => Target::Kms,
            Some("clear") => {
                if arguments.len() != 0 {
                    return Err("clear does not accept options".into());
                }
                return Ok(Self::Clear);
            }
            _ => return Err("expected window, kms or clear (see --help)".into()),
        };
        let mut duration = None;
        let mut hold = false;
        let mut dark = true;
        let mut snapshot = None;
        while let Some(argument) = arguments.next() {
            match argument.as_str() {
                "--duration" => duration = Some(arguments.next().ok_or("missing duration")?),
                "--hold" => hold = true,
                "--dark" => dark = true,
                "--light" => dark = false,
                "--snapshot" => snapshot = Some(arguments.next().ok_or("missing PNG path")?.into()),
                _ => return Err(format!("unknown option: {argument}").into()),
            }
        }
        if hold && (target != Target::Window || duration.is_some()) {
            return Err("--hold is only valid for window without --duration".into());
        }
        let duration = if hold {
            None
        } else {
            let value = duration
                .or(environment_duration)
                .unwrap_or_else(|| "3".to_owned());
            Some(
                Duration::try_from_secs_f64(value.parse()?)
                    .map_err(|_| "duration must be a finite, non-negative number of seconds")?,
            )
        };
        Ok(Self::Present(Options {
            target,
            duration,
            dark,
            snapshot,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_present(
        arguments: Vec<String>,
        environment_duration: Option<String>,
    ) -> Result<Options> {
        match Command::parse(arguments, environment_duration)? {
            Command::Present(options) => Ok(options),
            Command::Clear => Err("expected presentation command".into()),
        }
    }

    #[test]
    fn parses_clear_without_presentation_options() {
        assert!(matches!(
            Command::parse(vec!["clear".into()], Some("invalid".into())).unwrap(),
            Command::Clear
        ));
        assert!(Command::parse(vec!["clear".into(), "--dark".into()], None).is_err());
    }

    #[test]
    fn validates_duration_at_the_process_boundary() {
        for value in ["-1", "NaN", "inf", "1e300", "invalid"] {
            assert!(
                parse_present(
                    vec!["window".into(), "--duration".into(), value.into()],
                    None
                )
                .is_err()
            );
        }
        for value in ["0", "1.2", "3"] {
            let options = parse_present(
                vec!["window".into(), "--duration".into(), value.into()],
                None,
            )
            .unwrap();
            assert_eq!(
                options.duration.unwrap().as_secs_f64(),
                value.parse::<f64>().unwrap()
            );
        }
        assert_eq!(
            parse_present(vec!["kms".into()], None).unwrap().duration,
            Some(Duration::from_secs(3))
        );
        assert_eq!(
            parse_present(vec!["kms".into()], Some("3".into()))
                .unwrap()
                .duration,
            Some(Duration::from_secs(3))
        );
    }

    #[test]
    fn hold_is_window_only_and_overrides_environment_duration() {
        assert!(
            parse_present(vec!["window".into(), "--hold".into()], Some("3".into()))
                .unwrap()
                .duration
                .is_none()
        );
        for arguments in [
            vec!["kms", "--hold"],
            vec!["window", "--hold", "--duration", "0"],
        ] {
            assert!(
                parse_present(arguments.into_iter().map(String::from).collect(), None).is_err()
            );
        }
    }

    #[test]
    fn defaults_to_dark_with_an_explicit_light_override() {
        for target in ["window", "kms"] {
            assert!(parse_present(vec![target.into()], None).unwrap().dark);
            assert!(
                !parse_present(vec![target.into(), "--light".into()], None)
                    .unwrap()
                    .dark
            );
        }
    }
}
