(function () {
  'use strict';
  const config = window.INVITATION_CONFIG;
  const api = new window.InvitationAPI(config);
  const $ = selector => document.querySelector(selector);
  const safeUrl = window.InvitationUtils.safeUrl;
  let gifts = [], selectedGift, lastFocus, toastTimer, giftSignature = '';
  const icon = name => { const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); const use = document.createElementNS(svg.namespaceURI, 'use'); use.setAttribute('href', '#' + name); svg.append(use); svg.setAttribute('aria-hidden', 'true'); return svg; };
  const element = (tag, className, text) => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };
  function toast(message) { clearTimeout(toastTimer); $('#toast').textContent = message; $('#toast').hidden = false; toastTimer = setTimeout(() => $('#toast').hidden = true, 6500); }
  function topDialog() { return [...document.querySelectorAll('dialog[open]')].at(-1); }
  function openDialog(id) {
    const dialog = $(id), active = topDialog();
    if (dialog.open) return;
    if (!active) lastFocus = document.activeElement;
    // El catálogo permanece debajo de la reserva para conservar su posición al volver.
    if (active && active.id !== 'modal-regalos') active.close();
    document.body.style.overflow = 'hidden';
    dialog.showModal(); dialog.scrollTop = 0;
    if (id === '#modal-regalos') {
      dialog.querySelector('.gifts-sheet').scrollTop = 0;
      $('#view-all-gifts').setAttribute('aria-expanded', 'true');
    }
  }
  function success(title, message) { $('#success-title').textContent = title; $('#success-message').textContent = message; openDialog('#success-dialog'); }
  function showError(id, error) { $(id).textContent = error.message || 'Ocurrió un problema. Intenta de nuevo.'; $(id).hidden = false; $(id).scrollIntoView({ block: 'nearest' }); }
  function setSaving(button, saving, message) {
    button.disabled = saving;
    button.setAttribute('aria-busy', String(saving));
    const label = button.querySelector('span');
    if (saving) { label.dataset.readyText = label.textContent; label.textContent = message; }
    else if (label.dataset.readyText) { label.textContent = label.dataset.readyText; delete label.dataset.readyText; }
  }
  document.querySelectorAll('dialog').forEach(dialog => {
    dialog.addEventListener('close', () => {
      if (dialog.id === 'modal-regalos') $('#view-all-gifts').setAttribute('aria-expanded', 'false');
      const active = topDialog();
      if (!active) {
        document.body.style.overflow = document.body.classList.contains('sobre-cerrado') ? '' : 'auto';
        (lastFocus?.isConnected && !lastFocus.hidden ? lastFocus : $('#my-reservations'))?.focus();
      } else if (active.id === 'modal-regalos' && !active.contains(document.activeElement)) {
        active.querySelector('[data-close]').focus();
      }
    });
    dialog.addEventListener('click', event => {
      if (event.target !== dialog) return;
      if (dialog.id === 'modal-regalos') { dialog.close(); return; }
      const bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
    });
  });
  document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
  document.querySelectorAll('[data-rsvp]').forEach(button => button.addEventListener('click', () => { $('#rsvp-error').hidden = true; openDialog('#rsvp-dialog'); }));
  document.querySelectorAll('[data-baby-name]').forEach(node => node.textContent = config.babyName + (node.tagName === 'EM' ? '.' : ''));
  document.querySelectorAll('[data-family-name]').forEach(node => node.textContent = config.familyName.toLocaleUpperCase('es'));
  $('#preview-ribbon').hidden = !api.demo;
  $('#sample-gifts-note').hidden = !api.demo;
  document.querySelectorAll('[data-demo-note]').forEach(node => node.hidden = !api.demo);

  const date = new Date(config.eventDate + 'T12:00:00' + config.utcOffset);
  const day = new Intl.DateTimeFormat('es-CO', { weekday: 'long', timeZone: config.timeZone }).format(date);
  $('#event-day').textContent = day.charAt(0).toUpperCase() + day.slice(1);
  $('#event-month').textContent = new Intl.DateTimeFormat('es-CO', { month: 'long', timeZone: config.timeZone }).format(date).toLocaleUpperCase('es');
  $('#event-number').textContent = new Intl.DateTimeFormat('es-CO', { day: '2-digit', timeZone: config.timeZone }).format(date);
  $('#event-year').textContent = new Intl.DateTimeFormat('es', { year: 'numeric', timeZone: config.timeZone }).format(date);
  $('#event-date').setAttribute('datetime', config.eventDate);
  $('#countdown-wrap').classList.toggle('countdown--date-only', !config.eventTime);
  if (config.eventTime) {
    const instant = new Date(config.eventDate + 'T' + config.eventTime + ':00' + config.utcOffset);
    $('#event-time').textContent = new Intl.DateTimeFormat('es-CO', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: config.timeZone }).format(instant);
    $('#event-time-note').textContent = 'Hora de Colombia';
    $('#countdown-note').textContent = 'Para el comienzo de la celebración';
  }
  if (config.venue) $('#event-venue').textContent = config.venue;
  if (config.address) $('#event-address').textContent = config.address;
  const mapUrl = safeUrl(config.mapsUrl);
  if (mapUrl) { $('#maps-link').href = mapUrl; $('#maps-link').hidden = false; }
  if (config.rsvpDeadline) $('#rsvp-deadline').textContent = 'Confirma antes del ' + new Intl.DateTimeFormat('es-CO', { day: 'numeric', month: 'long', timeZone: config.timeZone }).format(new Date(config.rsvpDeadline + 'T12:00:00' + config.utcOffset)) + '.';
  function countdown() {
    const target = new Date(config.eventDate + 'T' + (config.eventTime || '00:00') + ':00' + config.utcOffset);
    const remaining = Math.max(0, target.getTime() - Date.now());
    let days = Math.floor(remaining / 86400000);
    if (!config.eventTime) {
      const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: 'numeric', day: 'numeric', timeZone: config.timeZone }).formatToParts(new Date());
      const value = type => Number(parts.find(part => part.type === type).value);
      const [year, month, day] = config.eventDate.split('-').map(Number);
      days = Math.max(0, Math.round((Date.UTC(year, month - 1, day) - Date.UTC(value('year'), value('month') - 1, value('day'))) / 86400000));
    }
    $('#days').textContent = String(days).padStart(2, '0');
    $('#hours').textContent = String(Math.floor(remaining / 3600000) % 24).padStart(2, '0');
    $('#minutes').textContent = String(Math.floor(remaining / 60000) % 60).padStart(2, '0');
    if (remaining === 0) $('#countdown-note').textContent = '¡Llegó el día de nuestra pequeña gran aventura!';
  }
  countdown(); setInterval(countdown, 30000);
  function icsEscape(text) { return String(text).replace(/\\/g, '\\\\').replace(/\r?\n/g, '\\n').replace(/,/g, '\\,').replace(/;/g, '\\;'); }
  function calendarFile() {
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Luciano//Baby Shower//ES', 'CALSCALE:GREGORIAN', 'BEGIN:VEVENT', 'UID:baby-shower-' + config.supabase.eventId + '@invitacion', 'DTSTAMP:' + new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z/, 'Z')];
    if (config.eventTime) {
      const start = new Date(config.eventDate + 'T' + config.eventTime + ':00' + config.utcOffset);
      const compact = d => d.toISOString().replace(/[-:]/g, '').replace(/\.\d+Z/, 'Z');
      lines.push('DTSTART:' + compact(start), 'DTEND:' + compact(new Date(start.getTime() + config.durationHours * 3600000)));
    } else {
      const next = new Date(config.eventDate + 'T12:00:00Z'); next.setUTCDate(next.getUTCDate() + 1);
      lines.push('DTSTART;VALUE=DATE:' + config.eventDate.replace(/-/g, ''), 'DTEND;VALUE=DATE:' + next.toISOString().slice(0, 10).replace(/-/g, ''));
    }
    lines.push('SUMMARY:' + icsEscape('Baby shower de ' + config.babyName), 'DESCRIPTION:' + icsEscape('¡Celebremos a ' + config.babyName + ' ' + config.familyName + '! ' + (!config.eventTime ? 'Hora por confirmar. ' : '') + (!config.venue ? 'Lugar por confirmar.' : '')), 'LOCATION:' + icsEscape([config.venue, config.address].filter(Boolean).join(', ') || 'Por confirmar'), 'END:VEVENT', 'END:VCALENDAR');
    const blob = new Blob([lines.join('\r\n') + '\r\n'], { type: 'text/calendar;charset=utf-8' });
    const link = document.createElement('a'); const url = URL.createObjectURL(blob); link.href = url; link.download = 'Baby-shower-Luciano.ics'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  $('#calendar-button').addEventListener('click', calendarFile);

  const audio = $('#event-audio'); audio.src = safeUrl(config.music.url, true); audio.volume = .55;
  $('#music-title').textContent = config.music.title;
  $('#music-subtitle').textContent = config.music.subtitle;
  function musicState(playing) { $('#music-toggle').setAttribute('aria-pressed', String(playing)); $('#music-toggle').setAttribute('aria-label', playing ? 'Pausar música' : 'Reproducir música'); $('#play-icon').textContent = playing ? 'Ⅱ' : '▶'; }
  $('#music-toggle').addEventListener('click', async () => {
    if (!audio.paused) { audio.pause(); return; }
    try { await audio.play(); } catch (_) { musicState(false); toast('No se pudo reproducir la canción. Intenta de nuevo.'); }
  });
  audio.addEventListener('play', () => musicState(true)); audio.addEventListener('pause', () => musicState(false)); audio.addEventListener('error', () => { musicState(false); });

  const rsvpForm = $('#rsvp-form');
  rsvpForm.addEventListener('change', () => { const attending = rsvpForm.elements.attending.value === 'yes'; $('#party-size-label').hidden = !attending; rsvpForm.elements.partySize.disabled = !attending; });
  rsvpForm.addEventListener('submit', async event => {
    event.preventDefault(); $('#rsvp-error').hidden = true;
    const submit = rsvpForm.querySelector('[type=submit]'); setSaving(submit, true, 'Guardando tu respuesta…');
    try {
      const fields = rsvpForm.elements;
      const attending = fields.attending.value === 'yes';
      await api.saveRsvp({ name: fields.name.value, attending, partySize: fields.partySize.value, message: fields.message.value });
      success(api.demo ? '¡Prueba guardada!' : attending ? '¡Qué alegría verte!' : 'Gracias por contarnos.', api.demo ? 'Tu respuesta de prueba se guardó solo en este navegador. Todavía no se ha enviado a los papás.' : attending ? 'Tu asistencia está confirmada. Nos llena de ilusión que seas parte de este día tan especial para Luciano.' : 'Recibimos tu respuesta. Aunque no puedas venir, sentimos todo tu cariño.');
    } catch (error) { showError('#rsvp-error', error); }
    finally { setSaving(submit, false); }
  });

  function giftCard(gift) {
    const card = element('article', 'gift-card');
    const allowedColors = ['sage', 'peach', 'sand'];
    const picture = element('div', 'gift-picture ' + (allowedColors.includes(gift.color) ? gift.color : 'sage'));
    picture.append(element('span', 'gift-category', gift.category || 'Para Luciano'));
    const image = safeUrl(gift.image_url);
    if (image) { const img = element('img'); img.src = image; img.alt = gift.name; img.loading = 'lazy'; img.referrerPolicy = 'no-referrer'; img.addEventListener('error', () => { img.remove(); picture.append(icon('i-gift')); }); picture.append(img); }
    else picture.append(icon('p-' + (['clothes','blanket','bath','book','bottle','bear'].includes(gift.icon) ? gift.icon : 'bear')));
    const content = element('div', 'gift-content'); content.append(element('h3', '', gift.name), element('p', '', gift.description || 'Un detalle para sus primeras aventuras.'));
    const actions = element('div', 'gift-actions'); const reserve = element('button', 'button reserve-button', 'Reservar regalo'); reserve.setAttribute('aria-label', 'Reservar ' + gift.name); reserve.append(icon('i-gift'));
    reserve.addEventListener('click', () => { selectedGift = gift; $('#selected-gift-name').textContent = gift.name; $('#gift-error').hidden = true; const person = rsvpForm.elements; const fields = $('#gift-form').elements; if (person.name.value) fields.name.value = person.name.value; openDialog('#gift-dialog'); });
    actions.append(reserve);
    const productUrl = safeUrl(gift.product_url);
    if (productUrl) { const link = element('a', 'gift-product-link', 'Ver en la tienda ↗'); link.setAttribute('aria-label', 'Ver ' + gift.name + ' en la tienda'); link.href = productUrl; link.target = '_blank'; link.rel = 'noopener noreferrer'; actions.append(link); }
    content.append(actions); card.append(picture, content); return card;
  }
  const giftCategories = [
    { id: 'ropita', label: 'Ropita', pattern: /rop(?:a|ita)|prenda|bod(?:y|ies)|pijama|vestir/, icons: ['clothes'] },
    { id: 'bano', label: 'Baño', pattern: /bano|aseo|higiene/, icons: ['bath'] },
    { id: 'alimentacion', label: 'Alimentación', pattern: /aliment|comer|teter|biber|lactancia/, icons: ['bottle'] },
    { id: 'accesorios', label: 'Accesorios', pattern: /acces|jugar|juguet|descubr|sueno|dormir|cuento|libro/, icons: ['blanket', 'book', 'bear'] },
  ];
  let activeGiftCategory = giftCategories[0].id, giftCategoriesReady = false, giftsLoadFailed = false;
  const giftViews = [
    { tabs: $('#gift-categories'), panels: $('#gift-grid'), prefix: 'gift', limit: 3 },
    { tabs: $('#all-gift-categories'), panels: $('#all-gifts-list'), prefix: 'all-gift', limit: Infinity },
  ];
  function categoryForGift(gift) {
    const category = String(gift.category || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es');
    return (giftCategories.find(item => item.pattern.test(category)) || giftCategories.find(item => item.icons.includes(gift.icon)))?.id || 'accesorios';
  }
  function groupedGifts() {
    const groups = new Map(giftCategories.map(category => [category.id, []]));
    gifts.forEach(gift => groups.get(categoryForGift(gift)).push(gift));
    return groups;
  }
  function syncGiftTabs() {
    giftViews.forEach(view => view.groups.forEach((group, category) => {
      const selected = category === activeGiftCategory;
      group.tab.setAttribute('aria-selected', String(selected));
      group.tab.tabIndex = selected ? 0 : -1;
      group.panel.hidden = !selected;
    }));
  }
  function updateGiftSummary(groups = groupedGifts()) {
    const category = giftCategories.find(item => item.id === activeGiftCategory);
    const count = groups.get(category.id).length;
    const countLabel = count + (count === 1 ? ' regalito disponible' : ' regalitos disponibles');
    $('#gift-count').textContent = category.label + ' · ' + (count > 3 ? 'Mostrando 3 de ' : '') + countLabel;
    $('#all-gift-count').textContent = category.label + ' · ' + countLabel;
    $('#view-all-gifts').hidden = count <= 3;
  }
  function selectGiftCategory(category, sourceView) {
    activeGiftCategory = category;
    syncGiftTabs(); if (!giftsLoadFailed) updateGiftSummary();
    if (sourceView === giftViews[1]) $('#modal-regalos').querySelector('.gifts-sheet').scrollTop = 0;
    sourceView?.groups.get(category).tab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
  giftViews.forEach(view => {
    view.groups = new Map();
    giftCategories.forEach((category, index) => {
      const tab = element('button', 'gift-tab'); tab.type = 'button';
      tab.id = view.prefix + '-tab-' + category.id;
      tab.setAttribute('role', 'tab');
      const count = element('span', 'gift-tab-count', '0'); count.setAttribute('aria-hidden', 'true');
      tab.append(element('span', '', category.label), count);
      const panel = element('div', 'gift-list gift-category-panel');
      panel.id = view.prefix + '-panel-' + category.id;
      panel.setAttribute('role', 'tabpanel'); panel.tabIndex = 0;
      panel.setAttribute('aria-labelledby', tab.id);
      tab.setAttribute('aria-controls', panel.id);
      tab.addEventListener('click', () => selectGiftCategory(category.id, view));
      tab.addEventListener('keydown', event => {
        let next;
        if (event.key === 'ArrowRight') next = (index + 1) % giftCategories.length;
        else if (event.key === 'ArrowLeft') next = (index - 1 + giftCategories.length) % giftCategories.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = giftCategories.length - 1;
        else return;
        event.preventDefault();
        const category = giftCategories[next].id;
        view.groups.get(category).tab.focus({ preventScroll: true });
        selectGiftCategory(category, view);
      });
      view.groups.set(category.id, { tab, count, panel });
      view.tabs.append(tab); view.panels.append(panel);
    });
  });
  syncGiftTabs();
  $('#view-all-gifts').addEventListener('click', () => openDialog('#modal-regalos'));
  function renderGiftList(list, items) {
    list.replaceChildren(...items.map(giftCard));
    if (!items.length) list.append(element('div', 'empty-state', gifts.length ? 'No hay regalitos disponibles en esta categoría. Puedes elegir otra pestaña.' : 'La lista está descansando por ahora. Tu presencia sigue siendo el mejor regalo.'));
  }
  async function refreshGifts() {
    try {
      gifts = await api.listGifts();
      giftsLoadFailed = false;
      const signature = JSON.stringify(gifts);
      const groups = groupedGifts();
      if (!giftCategoriesReady && gifts.length) {
        activeGiftCategory = giftCategories.find(category => groups.get(category.id).length).id;
        giftCategoriesReady = true;
      }
      if (signature !== giftSignature) {
        giftViews.forEach(view => giftCategories.forEach(category => {
          const items = groups.get(category.id), group = view.groups.get(category.id);
          renderGiftList(group.panel, items.slice(0, view.limit));
          group.count.textContent = String(items.length);
          group.tab.setAttribute('aria-label', category.label + ', ' + items.length + (items.length === 1 ? ' regalo disponible' : ' regalos disponibles'));
        }));
        syncGiftTabs();
        giftSignature = signature;
      }
      updateGiftSummary(groups);
      $('#reservation-count').textContent = String((await api.myGifts()).length);
    } catch (error) {
      giftsLoadFailed = true;
      giftSignature = '';
      $('#gift-count').textContent = 'No pudimos cargar la lista';
      $('#all-gift-count').textContent = 'No pudimos cargar la lista';
      $('#view-all-gifts').hidden = true;
      giftViews.forEach(view => view.groups.forEach(group => {
        group.count.textContent = '–';
        group.tab.setAttribute('aria-label', group.tab.querySelector('span').textContent + ', lista no disponible');
        const empty = element('div', 'empty-state'); empty.append(element('p', '', error.message));
        const retry = element('button', 'text-button', 'Volver a intentar'); retry.addEventListener('click', refreshGifts);
        empty.append(retry); group.panel.replaceChildren(empty);
      }));
    }
  }
  $('#gift-form').addEventListener('submit', async event => {
    event.preventDefault(); $('#gift-error').hidden = true;
    const form = event.currentTarget; const submit = form.querySelector('[type=submit]'); setSaving(submit, true, 'Guardando tu reserva…');
    try {
      const reserved = await api.reserveGift(selectedGift, { name: form.elements.name.value });
      if (!reserved) { await refreshGifts(); showError('#gift-error', new Error('Alguien acaba de reservar este regalito. Cierra esta ventana y elige otro detalle.')); return; }
      success(api.demo ? '¡Reserva de prueba lista!' : '¡Un detalle lleno de amor!', api.demo ? 'El regalo ya no aparece en tu lista de prueba. Esta reserva solo existe en este navegador y no aparta un regalo real.' : 'Reservaste “' + selectedGift.name + '”. Ya no aparecerá para otros invitados. Puedes consultar o cancelar tu reserva desde “Mis reservas” en este navegador.');
      await refreshGifts();
    } catch (error) { showError('#gift-error', error); }
    finally { setSaving(submit, false); }
  });
  async function renderReservations() {
    const list = $('#reservations-list'); list.replaceChildren(element('p', 'dialog-description', 'Consultando tus reservas…'));
    try {
      const mine = await api.myGifts(); list.replaceChildren();
      if (!mine.length) list.append(element('p', 'empty-state', 'Aún no tienes reservas en este navegador. Puedes escoger un regalito en la lista.'));
      for (const gift of mine) {
        const row = element('article', 'reservation-row'); row.append(element('h3', '', gift.name), element('p', '', api.demo ? 'Reserva de prueba · solo en este navegador' : 'Reservado con amor · pendiente de compra'));
        const actions = element('div', 'reservation-actions');
        const productUrl = safeUrl(gift.product_url);
        if (productUrl) { const link = element('a', 'text-button store-product-link', 'Ver en la tienda ↗'); link.href = productUrl; link.target = '_blank'; link.rel = 'noopener noreferrer'; actions.append(link); }
        const cancel = element('button', 'cancel-reservation', 'Cancelar reserva');
        cancel.addEventListener('click', async () => {
          if (cancel.dataset.confirm !== 'yes') { cancel.dataset.confirm = 'yes'; cancel.textContent = 'Sí, liberar este regalito'; return; }
          cancel.disabled = true;
          try { await api.cancelGift(gift); await renderReservations(); await refreshGifts(); toast('Reserva cancelada. El regalito vuelve a estar disponible.'); }
          catch (error) { toast(error.message); cancel.disabled = false; }
        });
        actions.append(cancel); row.append(actions); list.append(row);
      }
    } catch (error) { list.replaceChildren(element('p', 'form-error', error.message)); }
  }
  $('#my-reservations').addEventListener('click', () => { openDialog('#reservations-dialog'); renderReservations(); });
  window.addEventListener('storage', event => { if (event.key?.startsWith(api.namespace)) refreshGifts(); });
  window.addEventListener('focus', refreshGifts);
  setInterval(() => { if (!document.hidden) refreshGifts(); }, 20000);
  refreshGifts();
})();
