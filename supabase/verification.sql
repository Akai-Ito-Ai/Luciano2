-- Verificación manual después de cargar la lista real. No contiene datos personales de prueba.
-- Ejecutar en SQL Editor como postgres.
select c.relname as tabla, c.relrowsecurity as rls_activado
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('invitation_events','invitation_gifts','invitation_rsvps','invitation_gift_reservations');

-- Deben ser false: los visitantes no pueden leer datos personales directamente.
select has_table_privilege('anon','public.invitation_rsvps','select') as anon_lee_asistencias,
       has_table_privilege('anon','public.invitation_gift_reservations','select') as anon_lee_reservas;

-- La lista solo contiene metadatos de los regalos aún libres.
begin;
set local role anon;
select * from public.invitation_available_gifts('luciano-2026');
rollback;
