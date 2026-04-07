const demoVideos = Array.from(document.querySelectorAll("[data-demo-video]"));

if (demoVideos.length > 0) {
  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let reducedMotion = motionQuery.matches;

  const syncPausedState = (video) => {
    const frame = video.closest(".hero-demo-frame");
    video.classList.toggle("is-paused", video.paused);
    if (frame) {
      frame.classList.toggle("is-paused", video.paused);
    }
  };

  const playDemo = (video) => {
    const playback = video.play();
    if (playback && typeof playback.catch === "function") {
      playback.catch(() => {});
    }
  };

  const toggleDemoPlayback = (video) => {
    if (video.paused) {
      playDemo(video);
      return;
    }

    video.pause();
  };

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const video = entry.target;
        if (entry.isIntersecting) {
          if (!reducedMotion && video.paused) {
            playDemo(video);
          }
          return;
        }

        if (!video.paused) {
          video.pause();
        }
      });
    },
    { threshold: 0.25 }
  );

  demoVideos.forEach((video) => {
    video.addEventListener("play", () => syncPausedState(video));
    video.addEventListener("pause", () => syncPausedState(video));
    video.addEventListener("click", () => toggleDemoPlayback(video));
    video.addEventListener("keydown", (event) => {
      if (event.key !== " " && event.key !== "Enter") {
        return;
      }

      event.preventDefault();
      toggleDemoPlayback(video);
    });

    observer.observe(video);
    syncPausedState(video);
  });

  motionQuery.addEventListener("change", (event) => {
    reducedMotion = event.matches;

    demoVideos.forEach((video) => {
      if (reducedMotion) {
        if (!video.paused) {
          video.pause();
        }
        return;
      }

      if (video.paused && video.currentTime === 0) {
        playDemo(video);
      }
    });
  });
}
