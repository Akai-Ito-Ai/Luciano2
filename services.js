/* Sin dependencias: la misma interfaz para la vista previa y Supabase. */
(function () {
  'use strict';
  const SAMPLE_GIFTS = [
    { id: 'sample-clothes', name: 'Sus primeros bodies', description: 'Algodón suave para sus primeros descubrimientos.', category: 'Ropita', icon: 'clothes', color: 'sage' },
    { id: 'sample-blanket', name: 'Una mantita suave', description: 'Para envolverlo en abrazos y sueños bonitos.', category: 'Dulces sueños', icon: 'blanket', color: 'sand' },
    { id: 'sample-bath', name: 'Hora de burbujas', description: 'Una bañerita para sus primeras chapoteadas.', category: 'Hora del baño', icon: 'bath', color: 'peach' },
    { id: 'sample-book', name: 'Su primer cuento', description: 'Historias para leer muy cerquita del corazón.', category: 'A descubrir', icon: 'book', color: 'sand' },
    { id: 'sample-bottle', name: 'Un set de teteros', description: 'Pequeños momentos para crecer con amor.', category: 'A comer', icon: 'bottle', color: 'sage' },
    { id: 'sample-bear', name: 'Su primer amiguito', description: 'Un compañero suave para grandes aventuras.', category: 'A jugar', icon: 'bear', color: 'peach' },
  ];

  function safeUrl(value, allowRelative) {
    if (!value || typeof value !== 'string') return '';
    try {
      const url = new URL(value, 'https://invitation.local/');
      if (url.protocol !== 'https:' && !(allowRelative && url.protocol === 'http:')) return '';
      if (!allowRelative && url.origin === 'https://invitation.local') return '';
      return allowRelative ? value : url.href;
    } catch (_) { return ''; }
  }

  function validatePerson(data) {
    const name = String(data.name || '').trim();
    if (name.length < 2 || name.length > 100) throw new Error('Escribe tu nombre (entre 2 y 100 caracteres).');
    return { name };
  }

  class InvitationAPI {
    constructor(config, dependencies = {}) {
      this.config = config;
      this.storage = dependencies.storage || window.localStorage;
      this.fetch = dependencies.fetch || window.fetch.bind(window);
      const s = config.supabase || {};
      this.demo = !(s.url || s.publishableKey);
      this.invalidConfig = !this.demo && (!/^https:\/\/[^/]+\.supabase\.co\/?$/.test(s.url) || !s.publishableKey);
      this.namespace = 'luciano:' + (s.eventId || 'luciano-2026') + ':';
      // Never silently fall back to local storage after a failed database request.
    }
    read(key, fallback) {
      try { return JSON.parse(this.storage.getItem(this.namespace + key)) ?? fallback; }
      catch (_) { return fallback; }
    }
    write(key, value) {
      try { this.storage.setItem(this.namespace + key, JSON.stringify(value)); }
      catch (_) { throw new Error('El navegador no puede guardar los datos. Permite el almacenamiento para continuar.'); }
    }
    token(key) {
      let token = this.read(key, null);
      if (!token) { token = crypto.randomUUID(); this.write(key, token); }
      return token;
    }
    async rpc(name, params) {
      if (this.invalidConfig) throw new Error('La conexión aún no está lista. Avísales a los papás para que la revisen.');
      const options = this.config.supabase;
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15000);
      try {
        const headers = { 'Content-Type': 'application/json', apikey: options.publishableKey };
        // New sb_publishable_ keys are not JWTs and must not be sent as Bearer tokens.
        if (options.publishableKey.startsWith('eyJ')) headers.Authorization = 'Bearer ' + options.publishableKey;
        const response = await this.fetch(options.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
          method: 'POST', headers, body: JSON.stringify({ p_event_id: options.eventId, ...params }), signal: controller.signal,
        });
        const result = await response.json().catch(() => null);
        if (!response.ok) {
          if (result && result.code === 'P0001') throw new Error(result.message);
          throw new Error('No pudimos guardar tu respuesta. Intenta de nuevo en un momento.');
        }
        return result;
      } catch (error) {
        if (error.name === 'AbortError' || error instanceof TypeError) throw new Error('No logramos conectar. Revisa tu conexión e inténtalo de nuevo.');
        throw error;
      } finally { clearTimeout(timeout); }
    }
    async listGifts() {
      if (!this.demo) return this.rpc('invitation_available_gifts', {});
      const reserved = this.read('demo-reservations', {});
      return SAMPLE_GIFTS.filter(g => !reserved[g.id]).map(g => ({ ...g }));
    }
    async saveRsvp(data) {
      const person = validatePerson(data);
      const partySize = data.attending ? Number(data.partySize) : 0;
      const message = String(data.message || '').trim();
      if (typeof data.attending !== 'boolean' || !Number.isInteger(partySize) || (data.attending && (partySize < 1 || partySize > 6)) || message.length > 500) throw new Error('Revisa el número de asistentes y tu mensaje.');
      const token = this.token('rsvp-token');
      const payload = { ...person, attending: data.attending, partySize, message };
      if (this.demo) this.write('demo-rsvp', payload);
      else await this.rpc('invitation_save_rsvp', { p_token: token, p_name: person.name, p_attending: data.attending, p_party_size: partySize, p_message: message });
      // Only cache successful writes. Personal contact data is not cached in live mode.
      this.write('rsvp-status', { attending: data.attending, savedAt: new Date().toISOString() });
      return payload;
    }
    async reserveGift(gift, data) {
      const person = validatePerson(data);
      const token = this.token('gift-token:' + gift.id);
      if (this.demo) {
        const reservations = this.read('demo-reservations', {});
        if (reservations[gift.id] && reservations[gift.id].token !== token) return false;
        reservations[gift.id] = { token, name: person.name };
        this.write('demo-reservations', reservations);
      } else {
        const reserved = await this.rpc('invitation_reserve_gift', { p_gift_id: gift.id, p_token: token, p_name: person.name });
        if (!reserved) return false;
      }
      const mine = this.read('my-gifts', []);
      if (!mine.some(g => g.id === gift.id)) this.write('my-gifts', [...mine, { id: gift.id, name: gift.name, product_url: gift.product_url || '', token }]);
      return true;
    }
    async myGifts() {
      const mine = this.read('my-gifts', []);
      if (this.demo) return mine.filter(g => this.read('demo-reservations', {})[g.id]?.token === g.token);
      if (!mine.length) return [];
      const active = await this.rpc('invitation_my_gifts', { p_tokens: mine.map(g => g.token) });
      const reconciled = active.map(g => ({ ...g, token: mine.find(m => m.id === g.id)?.token })).filter(g => g.token);
      this.write('my-gifts', reconciled);
      return reconciled;
    }
    async cancelGift(gift) {
      if (this.demo) {
        const reservations = this.read('demo-reservations', {});
        if (reservations[gift.id]?.token === gift.token) { delete reservations[gift.id]; this.write('demo-reservations', reservations); }
      } else await this.rpc('invitation_cancel_gift', { p_gift_id: gift.id, p_token: gift.token });
      this.write('my-gifts', this.read('my-gifts', []).filter(g => g.id !== gift.id));
    }
  }
  window.InvitationAPI = InvitationAPI;
  window.InvitationUtils = { safeUrl, validatePerson };
})();
