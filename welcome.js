/* El sello abre el sobre una sola vez por visita y habilita la tarjeta. */
(function () {
  'use strict';
  const envelope = document.querySelector('#sobre');
  const seal = document.querySelector('#abrir-invitacion');
  const invitation = document.querySelector('#invitacion');
  const title = document.querySelector('#hero-title');
  if (!envelope || !seal || !invitation) return;
  let opening = false;
  let opened = false;
  let fallback;

  function finishOpening() {
    if (opened) return;
    opened = true;
    clearTimeout(fallback);
    document.body.classList.remove('sobre-cerrado');
    invitation.removeAttribute('inert');
    invitation.removeAttribute('aria-hidden');
    envelope.hidden = true;
    envelope.removeAttribute('aria-busy');
    window.scrollTo(0, 0);
    document.dispatchEvent(new Event('invitation:opened'));
    if (title) title.focus({ preventScroll: true });
  }

  seal.addEventListener('click', () => {
    if (opening) return;
    opening = true;
    seal.disabled = true;
    seal.setAttribute('aria-expanded', 'true');
    envelope.setAttribute('aria-busy', 'true');
    window.scrollTo(0, 0);
    envelope.classList.add('abierto');
    // Respaldo por si el navegador no emite transitionend, sin dejar bloqueado el scroll.
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    fallback = setTimeout(finishOpening, reduced ? 0 : 1100);
  });
  envelope.addEventListener('transitionend', event => {
    if (opening && event.target === envelope && event.propertyName === 'transform') finishOpening();
  });
  envelope.addEventListener('keydown', event => {
    if (event.key === 'Tab' && !opening) { event.preventDefault(); seal.focus(); }
  });
  window.addEventListener('load', () => { if (!opening) window.scrollTo(0, 0); }, { once: true });
  window.scrollTo(0, 0);
  seal.focus({ preventScroll: true });
})();
