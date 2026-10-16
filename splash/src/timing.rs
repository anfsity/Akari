use std::time::{Duration, Instant};

/// Construction and decoding do not start the clock. Only a successful
/// presentation starts the minimum hold, and resizing never restarts it.
pub struct Presentation {
    first: Option<Instant>,
    duration: Option<Duration>,
}

impl Presentation {
    pub fn new(duration: Option<Duration>) -> Self {
        Self {
            first: None,
            duration,
        }
    }

    pub fn mark_presented(&mut self, now: Instant) {
        self.first.get_or_insert(now);
    }

    pub fn get_elapsed(&self, now: Instant) -> Duration {
        self.first
            .map_or(Duration::ZERO, |first| now.duration_since(first))
    }

    pub fn is_finished(&self, now: Instant) -> bool {
        self.first
            .zip(self.duration)
            .is_some_and(|(first, duration)| now.duration_since(first) >= duration)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_presentation_starts_the_hold_and_later_frames_do_not_reset_it() {
        let mut timing = Presentation::new(Some(Duration::from_millis(1200)));
        let after_build = Instant::now() + Duration::from_secs(60);
        assert!(!timing.is_finished(after_build));
        timing.mark_presented(after_build);
        timing.mark_presented(after_build + Duration::from_millis(1000));
        assert!(!timing.is_finished(after_build + Duration::from_millis(1199)));
        assert!(timing.is_finished(after_build + Duration::from_millis(1200)));
    }

    #[test]
    fn zero_still_requires_a_presented_frame() {
        let mut timing = Presentation::new(Some(Duration::ZERO));
        let now = Instant::now();
        assert!(!timing.is_finished(now));
        timing.mark_presented(now);
        assert!(timing.is_finished(now));
    }

    #[test]
    fn held_presentation_does_not_expire() {
        let mut timing = Presentation::new(None);
        let now = Instant::now();
        timing.mark_presented(now);
        assert!(!timing.is_finished(now + Duration::from_secs(3600)));
    }
}
