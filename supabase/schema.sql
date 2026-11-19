-- Ejecutar UNA VEZ en SQL Editor de un proyecto Supabase dedicado a esta invitación.
-- No expone nombres, correos ni respuestas a los invitados. No requiere service_role en la web.
begin;

create table public.invitation_events (
  id text primary key,
  name text not null,
  enabled boolean not null default true
);
create table public.invitation_gifts (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.invitation_events(id),
  name text not null check (char_length(name) between 2 and 100),
  description text not null default '' check (char_length(description) <= 300),
  category text not null default 'Para Luciano',
  icon text not null default 'bear' check (icon in ('clothes','blanket','bath','book','bottle','bear')),
  color text not null default 'sage' check (color in ('sage','peach','sand')),
  image_url text not null default '' check (image_url = '' or image_url ~ '^https://'),
  product_url text not null default '' check (product_url = '' or product_url ~ '^https://'),
  sort_order integer not null default 0,
  enabled boolean not null default true,
  unique(event_id,id)
);
create table public.invitation_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.invitation_events(id),
  receipt_token uuid not null,
  name text not null check (char_length(name) between 2 and 100),
  email text check (char_length(email) <= 254),
  attending boolean not null,
  party_size integer not null,
  message text not null default '' check (char_length(message) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, receipt_token),
  unique (event_id, email),
  check ((attending and party_size between 1 and 6) or (not attending and party_size = 0))
);
create table public.invitation_gift_reservations (
  gift_id uuid primary key,
  event_id text not null,
  receipt_token uuid not null unique,
  name text not null check (char_length(name) between 2 and 100),
  email text check (char_length(email) <= 254),
  created_at timestamptz not null default now(),
  foreign key (event_id,gift_id) references public.invitation_gifts(event_id,id)
);

alter table public.invitation_events enable row level security;
alter table public.invitation_gifts enable row level security;
alter table public.invitation_rsvps enable row level security;
alter table public.invitation_gift_reservations enable row level security;
revoke all on public.invitation_events, public.invitation_gifts, public.invitation_rsvps, public.invitation_gift_reservations from anon, authenticated;
-- Sin políticas de acceso directo. Las operaciones permitidas se exponen mediante funciones acotadas.

create function public.invitation_available_gifts(p_event_id text)
returns table(id uuid, name text, description text, category text, icon text, color text, image_url text, product_url text)
language sql stable security definer set search_path = '' as $$
  select g.id,g.name,g.description,g.category,g.icon,g.color,g.image_url,g.product_url
  from public.invitation_gifts g
  join public.invitation_events e on e.id=g.event_id and e.enabled
  where g.event_id=p_event_id and g.enabled
    and not exists(select 1 from public.invitation_gift_reservations r where r.gift_id=g.id)
  order by g.sort_order,g.name;
$$;

create function public.invitation_save_rsvp(p_event_id text,p_token uuid,p_name text,p_attending boolean,p_party_size integer,p_message text default '')
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

create function public.invitation_reserve_gift(p_event_id text,p_gift_id uuid,p_token uuid,p_name text)
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

create function public.invitation_my_gifts(p_event_id text,p_tokens uuid[])
returns table(id uuid,name text,product_url text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(cardinality(p_tokens),0)>100 then raise exception 'Demasiadas reservas en una sola consulta.'; end if;
  return query select g.id,g.name,g.product_url from public.invitation_gift_reservations r
  join public.invitation_gifts g on g.id=r.gift_id
  where r.event_id=p_event_id and r.receipt_token=any(p_tokens);
end;
$$;

create function public.invitation_cancel_gift(p_event_id text,p_gift_id uuid,p_token uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  delete from public.invitation_gift_reservations where event_id=p_event_id and gift_id=p_gift_id and receipt_token=p_token;
  -- No revela si existía una reserva con otro token.
  return true;
end;
$$;

revoke all on function public.invitation_available_gifts(text) from public;
revoke all on function public.invitation_save_rsvp(text,uuid,text,boolean,integer,text) from public;
revoke all on function public.invitation_reserve_gift(text,uuid,uuid,text) from public;
revoke all on function public.invitation_my_gifts(text,uuid[]) from public;
revoke all on function public.invitation_cancel_gift(text,uuid,uuid) from public;
grant execute on function public.invitation_available_gifts(text) to anon,authenticated;
grant execute on function public.invitation_save_rsvp(text,uuid,text,boolean,integer,text) to anon,authenticated;
grant execute on function public.invitation_reserve_gift(text,uuid,uuid,text) to anon,authenticated;
grant execute on function public.invitation_my_gifts(text,uuid[]) to anon,authenticated;
grant execute on function public.invitation_cancel_gift(text,uuid,uuid) to anon,authenticated;

insert into public.invitation_events(id,name) values('luciano-2026','Baby shower de Luciano Mejía Villamizar');
-- La lista real se agrega en Table Editor > invitation_gifts. No se cargan regalos de ejemplo.
commit;
