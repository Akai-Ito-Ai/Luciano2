-- Permite confirmar y reservar con nombre, sin solicitar ni inventar correos.
-- Conserva datos previos, tokens, RLS y las firmas antiguas para páginas en caché.
begin;

alter table public.invitation_rsvps alter column email drop not null;
alter table public.invitation_gift_reservations alter column email drop not null;

create or replace function public.invitation_save_rsvp(p_event_id text,p_token uuid,p_name text,p_attending boolean,p_party_size integer,p_message text default '')
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.invitation_events where id=p_event_id and enabled) then
    raise exception 'Esta invitación no está recibiendo respuestas en este momento.';
  end if;
  if p_token is null or p_name is null or char_length(btrim(p_name)) not between 2 and 100
     or p_attending is null or p_party_size is null
     or (p_attending and p_party_size not between 1 and 6)
     or (not p_attending and p_party_size<>0)
     or char_length(coalesce(p_message,''))>500 then
    raise exception 'Revisa tu nombre y número de asistentes.';
  end if;
  insert into public.invitation_rsvps(event_id,receipt_token,name,attending,party_size,message)
  values(p_event_id,p_token,btrim(p_name),p_attending,p_party_size,btrim(coalesce(p_message,'')))
  on conflict(event_id,receipt_token) do update
    set name=excluded.name,attending=excluded.attending,party_size=excluded.party_size,
        message=excluded.message,updated_at=now();
  return true;
end;
$$;

create or replace function public.invitation_reserve_gift(p_event_id text,p_gift_id uuid,p_token uuid,p_name text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_token is null or p_name is null or char_length(btrim(p_name)) not between 2 and 100 then
    raise exception 'Escribe tu nombre (entre 2 y 100 caracteres).';
  end if;
  if not exists(select 1 from public.invitation_gifts g join public.invitation_events e on e.id=g.event_id
    where g.id=p_gift_id and g.event_id=p_event_id and g.enabled and e.enabled) then
    raise exception 'Este regalito ya no está disponible.';
  end if;
  insert into public.invitation_gift_reservations(gift_id,event_id,receipt_token,name)
    values(p_gift_id,p_event_id,p_token,btrim(p_name))
    on conflict (gift_id) do nothing;
  return exists(select 1 from public.invitation_gift_reservations where gift_id=p_gift_id and event_id=p_event_id and receipt_token=p_token);
end;
$$;

revoke all on function public.invitation_save_rsvp(text,uuid,text,boolean,integer,text) from public;
revoke all on function public.invitation_reserve_gift(text,uuid,uuid,text) from public;
grant execute on function public.invitation_save_rsvp(text,uuid,text,boolean,integer,text) to anon,authenticated;
grant execute on function public.invitation_reserve_gift(text,uuid,uuid,text) to anon,authenticated;

notify pgrst,'reload schema';
commit;
