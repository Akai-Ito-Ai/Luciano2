/* Los cuatro dinosaurios decorativos se cargan y reproducen al entrar en pantalla. */
(function () {
  'use strict';
  const videos = Array.from(document.querySelectorAll('[data-decoration]'));
  const toggle = document.querySelector('#motion-toggle');
  if (!videos.length || !toggle) return;

  const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
  const storageKey = 'luciano:decorations-paused';
  const visible = new Set();
  let savedPause = false;
  try { savedPause = window.localStorage.getItem(storageKey) === 'true'; } catch (_) { /* Opcional. */ }
  let paused = preference.matches || savedPause;

  function shouldPlay(video) {
    return !paused && !document.hidden && !document.body.classList.contains('sobre-cerrado') && visible.has(video) && !video.dataset.failed;
  }

  function syncVideo(video) {
    if (!shouldPlay(video)) { video.pause(); return; }
    if (!video.getAttribute('src')) {
      // También se establece como propiedad para la reproducción inline en iPhone.
      video.muted = true;
      video.defaultMuted = true;
      video.src = video.dataset.src;
      video.load();
    }
    const playback = video.play();
    if (playback && typeof playback.then === 'function') {
      playback.then(() => { if (!shouldPlay(video)) video.pause(); }).catch(() => {
        // Si el navegador limita autoplay, queda la imagen fija sin bloquear la invitación.
      });
    }
  }

  function syncAll() {
    toggle.hidden = false;
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.querySelector('span').textContent = paused ? 'Activar animaciones' : 'Pausar animaciones';
    toggle.querySelector('use').setAttribute('href', paused ? '#i-play' : '#i-pause');
    videos.forEach(syncVideo);
  }

  videos.forEach(video => {
    video.muted = true;
    video.defaultMuted = true;
    video.addEventListener('error', () => {
      video.dataset.failed = 'true';
      video.pause();
      video.removeAttribute('src');
      video.load(); // Restablece el poster si un archivo no está disponible.
    }, { once: true });
  });

  toggle.addEventListener('click', () => {
    paused = !paused;
    savedPause = paused;
    try { window.localStorage.setItem(storageKey, String(paused)); } catch (_) { /* Opcional. */ }
    syncAll();
  });

  const onPreferenceChange = event => { paused = event.matches || savedPause; syncAll(); };
  if (preference.addEventListener) preference.addEventListener('change', onPreferenceChange);
  else preference.addListener(onPreferenceChange);
  document.addEventListener('visibilitychange', () => videos.forEach(syncVideo));
  document.addEventListener('invitation:opened', syncAll);

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) visible.add(entry.target);
        else visible.delete(entry.target);
        syncVideo(entry.target);
      });
    }, { threshold: 0.08 });
    videos.forEach(video => observer.observe(video));
  } else {
    const checkVisibility = () => {
      videos.forEach(video => {
        const rect = video.getBoundingClientRect();
        if (rect.bottom > 0 && rect.top < window.innerHeight) visible.add(video);
        else visible.delete(video);
        syncVideo(video);
      });
    };
    window.addEventListener('scroll', checkVisibility, { passive: true });
    window.addEventListener('resize', checkVisibility);
    checkVisibility();
  }
  syncAll();
})();
