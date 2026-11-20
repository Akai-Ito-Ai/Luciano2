/* Los únicos datos que necesitan editar para personalizar la invitación. */
window.INVITATION_CONFIG = {
  babyName: 'Luciano',
  familyName: 'Mejía Villamizar',
  eventDate: '2026-12-13',
  eventTime: '15:00', // Ejemplo: '15:00'. Vacío = por confirmar.
  timeZone: 'America/Bogota',
  utcOffset: '-05:00',
  durationHours: 3,
  venue: 'Salón Comunal Belaire',
  address: 'Carrera 6 # 151 - 79',
  mapsUrl: 'https://maps.app.goo.gl/vcwxVgJ2M82gq2Yv6', // URL completa de Google Maps.
  rsvpDeadline: '', // Ejemplo: '2026-12-05'.
  music: {
    url: 'assets/cancion_luciano.m4a',
    title: 'Una canción para Luciano',
    subtitle: 'Un momento para celebrar juntos',
  },
  supabase: {
    url: 'https://cmmnikvsrfnpweviswtz.supabase.co',
    publishableKey: 'sb_publishable_Xsn5vq28Rg7xLoiqq3jrpQ_3ZxIPfxO', // Solo publishable o anon. NUNCA service_role ni una contraseña.
    eventId: 'luciano-2026',
  },
};
