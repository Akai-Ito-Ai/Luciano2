-- Actualización del 18 de noviembre de 2026. Conserva las reservas existentes.
begin;
create temp table luciano_before_update on commit drop as
select
 (select coalesce(array_agg(gift_id order by gift_id),array[]::uuid[]) from public.invitation_gift_reservations where event_id='luciano-2026') as reserved_ids,
 (select coalesce(array_agg(receipt_token order by receipt_token),array[]::uuid[]) from public.invitation_rsvps where event_id='luciano-2026') as rsvp_tokens;
create temp table luciano_gift_states on commit drop as
select id,enabled from public.invitation_gifts where event_id='luciano-2026';
-- Permite confirmar y reservar con nombre, sin solicitar ni inventar correos.
-- Conserva datos previos, tokens, RLS y las firmas antiguas para páginas en caché.

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
-- Lista de los papás, importación del 2026-11-18.
-- Importación repetible: conserva IDs, reservas, imágenes existentes y estado enabled.
insert into public.invitation_events(id,name) values ('luciano-2026','Baby shower de Luciano Mejía Villamizar') on conflict(id) do nothing;
insert into public.invitation_gifts (id,event_id,name,description,category,icon,color,image_url,product_url,sort_order,enabled) values
('1e3cad8c-49a9-5c09-a7dc-d05bfe49adaf','luciano-2026','Máquina de sonidos y luz nocturna Momcozy','Máquina de ruido blanco para ayudar con la rutina de descanso. Control desde app, sonidos relajantes y luz nocturna; recargable por USB-C.','Accesorios','blanket','sand','','https://www.amazon.com/dp/B099RSXLGH?th=1',10,true),
('d98d73ce-6249-504d-ae7e-f457c68483be','luciano-2026','Lima eléctrica de uñas Momcozy','Cortauñas/lima eléctrica recargable para bebés, con luz y discos intercambiables; incluye accesorios para diferentes edades.','Baño','bath','peach','','https://www.amazon.com/dp/B0CL4G33BX?th=1',20,true),
('cdc2b8fa-9a69-540a-9331-e0bf6bb99724','luciano-2026','Bolsas para almacenar leche materna Momcozy','Paquete de 200 bolsas preesterilizadas de 6 oz para conservar o congelar leche materna; doble cierre e indicador de temperatura.','Alimentación','bottle','sage','','https://www.amazon.com/dp/B0B511FV9Y?th=1',30,true),
('cacd380b-3400-5278-bc35-34242e3dbd62','luciano-2026','Sacos de dormir de algodón Wrrernsin (3 unidades)','Juego de 3 sacos de dormir ligeros de algodón, 0.5 TOG, con cremallera bidireccional para facilitar el cambio de pañal;','Ropita','clothes','sage','','https://www.amazon.com/dp/B0F2F3KP3R?th=1',40,true),
('67060068-16f5-5121-83d5-e80d7c2610f9','luciano-2026','Toallitas de baño para bebé','Toallitas suaves y absorbentes para la higiene y el baño de bebés y niños pequeños.','Baño','bath','peach','','https://www.amazon.com/dp/B0GXJVHL92?th=1',50,true),
('3604bd09-b739-531c-951f-1d9405e2d2cb','luciano-2026','Gimnasio musical Baby Einstein Kickin’ Tunes 4 en 1','Gimnasio de actividades con piano musical y juguetes para estimular movimientos, sonidos y juego boca arriba o boca abajo.','Accesorios','bear','sand','','https://www.amazon.com/dp/B07MPCCDM7?th=1',60,true),
('29527d61-9999-5e74-8f67-ae7d5b3de5ca','luciano-2026','Set de recién nacido Philips Avent Natural Response','Set de regalo para recién nacido con 6 biberones y chupete; tetinas Natural Response que permiten al bebé controlar el flujo al succionar.','Alimentación','bottle','sage','','https://www.amazon.com/dp/B0G6GRJHNM',70,true),
('4ffca606-eeea-5d95-93b5-8a989ad22c02','luciano-2026','Bañera plegable AVIDOR para bebé','Bañera portátil y plegable color gris, con soporte/red suave para recién nacido, patas antideslizantes y diseño de dinosaurio.','Baño','bath','peach','','https://www.amazon.com/dp/B0DP2KY486?th=1',80,true),
('3e67ea6d-a016-560b-bfd9-f363ec3c7a7a','luciano-2026','Libro sensorial de tela beiens para bebé','Libro blando con páginas de tela que crujen y diferentes texturas; estimulación sensorial y juego durante tummy time.','Accesorios','book','sand','','https://www.amazon.com/dp/B07TXYC6WD?th=1',90,true),
('5209b78b-fb14-5b12-a150-e188cf98beda','luciano-2026','Libro sensorial Montessori Macabaka','Libro de tela blando con 8 páginas interactivas, texturas, papel crujiente y espejo seguro para bebé; para exploración táctil.','Accesorios','book','sand','','https://www.amazon.com/dp/B0F7LFRKLK?th=1',100,true),
('34950fe0-df28-5828-af0d-0faed0b42797','luciano-2026','Baberos bandana Konssy de muselina (8 unidades)','Paquete de 8 baberos ajustables para la saliva y dentición, con frente de algodón tipo muselina y reverso absorbente.','Ropita','clothes','sage','','https://www.amazon.com/dp/B0BD6Y6M9V?th=1',110,true),
('3f7894db-be74-5db6-bed1-15fe18ebb666','luciano-2026','Aspirador nasal eléctrico GROWNSY','Aspirador nasal recargable con niveles de succión ajustables, puntas de silicona, luz y música; cámara de recolección desmontable.','Baño','bath','peach','','https://www.amazon.com/dp/B08CMWHD3B?th=1',120,true),
('a37fd528-4da0-5a0e-8e0a-d6b162974fbd','luciano-2026','Cargador BabbleRoo','Cargador verde 6 en 1 con soporte lumbar','Accesorios','bear','sand','','https://www.amazon.com/dp/B0FHH22YQ4?th=1',130,true),
('bbad2b58-ae23-59a3-901f-c0baa80d0f0a','luciano-2026','Esterilizador y secador de biberones Momcozy 4 en 1','','Alimentación','bottle','sage','','https://www.amazon.com/dp/B0FCF7TT5Z',140,true),
('4844475f-acd6-528a-b03e-8ebb5f913503','luciano-2026','Columpio eléctrico para bebé RIVIPLOU','Columpio portátil color gris con control remoto, cinco velocidades de movimiento y asiento acolchado desmontable;','Accesorios','bear','sand','','https://www.amazon.com/dp/B0DQ819LTK?th=1',150,true),
('7be6fa1b-2d59-5e86-aa96-4023f5ab61ca','luciano-2026','Corral cuna colecho Madison Plus Priori gris','Cuna corral plegable con función colecho, dos alturas, cambiador desmontable, mosquitero y túnel de juego; capacidad máxima del corral 15 kg.','Accesorios','blanket','sand','','https://centraldelbebe.com/products/corral-cuna-colecho-madison-plus-priori-gris?variant=47958801481833&country=CO&currency=COP',160,true),
('c6365627-f081-5828-8bd4-74bb642fb1b1','luciano-2026','Kit de lactancia Nubba by Toral','Kit de apoyo para lactancia con almohadón materno y dos mantas;','Alimentación','bottle','sage','','https://www.falabella.com.co/falabella-co/product/152263778/kit-de-lactancia-bebe-nubba-by-toral/152263779',170,true),
('65a09d50-2ec7-5e06-a131-e1eb2ea18a4a','luciano-2026','Sábana para cuna corral de bebé 60 × 90 cm','Sábana para colchón de cuna corral de 60 × 90 cm.','Accesorios','blanket','sand','','https://www.falabella.com.co/falabella-co/product/152928788/sabana-para-cuna-corral-de-bebe-60x90/152928789',180,true),
('75dcf67f-64d8-5040-8085-24a5f0f97c06','luciano-2026','Combo IKSA de colchón para cuna 60 × 90 × 11 cm (5 piezas)','Set para cuna con colchón, protector antifluidos, sábana ajustable, funda y almohada. La ficha indica 60 × 90 × 11 cm,','Accesorios','blanket','sand','','https://www.falabella.com.co/falabella-co/product/126246023/Combo-Colchon-5-piezas-para-cuna-de-60x90x11/126246024',190,true),
('0d36b0e4-0e49-52ee-8f8e-487f575f240c','luciano-2026','Sábana para cuna corral de bebé 60 × 90 cm','Sábana para colchón de cuna corral de 60 × 90 cm.','Accesorios','blanket','sand','','https://www.falabella.com.co/falabella-co/product/152928788/sabana-para-cuna-corral-de-bebe-60x90/152928789',200,true),
('d7097ffe-2522-5e66-9201-083243aed22d','luciano-2026','Nido para recién nacido Baby On azul','Nido acolchado de tela suave, presentado como hipoalergénico, para colocar al bebé cuando está despierto y supervisado.','Accesorios','bear','sand','','https://www.falabella.com.co/falabella-co/product/156061811/nido-bebe-recien-nacido-cuna-segura-comoda-almohada-baby-on-tela-suave-hipoalergenica-azul/156061812',210,true),
('492277f2-9315-51f2-b4cf-120862f36551','luciano-2026','Coche travel system Bebesit Cosmos beige','Sistema de paseo para bebé modelo Cosmos en color beige.','Accesorios','bear','sand','','https://www.exito.com/coche-travesystem-cosmos-beige-bebesit-5284bg-3074579/p?idsku=3224072',220,true),
('82d43be8-50da-5c90-9d1e-21ae032d962e','luciano-2026','Kit de juego para el desarrollo del bebé Taf Toys','Set de actividades de Taf Toys para estimular la exploración sensorial y el desarrollo temprano.','Accesorios','bear','sand','','https://www.babycentro.com/products/kit-de-juego-para-el-desarrollo-del-bebe-taf-toys',230,true),
('5786d9e3-0d04-5347-b7ea-85ddbc6dde90','luciano-2026','Combo limpiador de teteros para bebé (7 elementos)','Kit de siete elementos para la limpieza de biberones/teteros y accesorios de alimentación.','Alimentación','bottle','sage','','https://www.babycentro.com/products/combo-limpiador-de-teteros-para-bebe-7-elementos',240,true),
('33ac22c5-4cc3-508a-9e7d-442a08c00bdf','luciano-2026','Kit blanco y negro para recién nacido Taf Toys','Kit de estimulación visual temprana con diseños de alto contraste en blanco y negro, pensado para acompañar los primeros meses.','Accesorios','bear','sand','','https://www.babycentro.com/products/kit-blanco-y-negro-recien-nacido-taf-toys',250,true),
('d0141185-64c1-5cd5-9c0f-237aa5bea3a6','luciano-2026','Solución limpiadora Mustela 300 ml','Solución limpiadora para la higiene del bebé de la marca Mustela en presentación de 300 ml.','Baño','bath','peach','','https://www.farmatodo.com.co/producto/500027000-solucion-limpiadora-300ml-mustela--botella--x-300',260,true),
('008c741b-dead-5835-a40f-2a0f22ddd8c1','luciano-2026','Ruana de pollito Dos Micos','Ruana infantil con diseño de pollito para abrigar al bebé.','Ropita','clothes','sage','','https://dosmicos.co/products/ruana-de-pollito',270,true),
('d99c8ce5-1600-559e-be32-b56279c5d613','luciano-2026','Pack de bodies Bodycool manga corta','Paquete de bodies de manga corta para bebé, línea Bodycool.','Ropita','clothes','sage','','https://www.falabella.com.co/falabella-co/product/883876430/pack-body-bodycoolmc/883876443',280,true),
('a9b34aec-6ee4-580e-a784-2ff2d9bc23fa','luciano-2026','Contenedor de pañales antiolor Coccololo','Contenedor especial para desechar pañales y ayudar a contener los malos olores.','Accesorios','bear','sand','','https://www.coccoylolo.com/products/contenedor-panales-antiolor',290,true),
('4b308d8c-dae9-53a6-9bbc-6fa2dbb42dc8','luciano-2026','Silla cojín con espuma estabilizadora para bebé niño','Asiento/cojín acolchado con espuma estabilizadora para uso supervisado del bebé.','Accesorios','bear','sand','','https://www.falabella.com.co/falabella-co/product/155432946/silla-cojin-con-espuma-estabilizadora-para-bebe-nino/155432950',300,true),
('97d7f43c-9c10-5160-bada-b5941452fe04','luciano-2026','Pijama de franela para recién nacido niño','Pijama infantil de franela para recién nacido.','Ropita','clothes','sage','','https://www.falabella.com.co/falabella-co/product/883760186/pijama-r-n-nin-pjfranelax/883760187',310,true),
('1b61983a-7d7e-5f98-b7c2-cfd86eb14226','luciano-2026','Pack de 7 bodies para bebé','Paquete de siete bodies para bebé.','Ropita','clothes','sage','','https://www.falabella.com.co/falabella-co/product/883772063/pack-body-bodyx7dvdm/883772073',320,true),
('e26cc943-f9f4-508e-8f3e-e02bb813cfdb','luciano-2026','Conjunto de 3 piezas rojo Glotoncitos para bebé niño','Conjunto de ropa para bebé niño de tres piezas en color rojo, marca Glotoncitos.','Ropita','clothes','sage','','https://www.falabella.com.co/falabella-co/product/151988599/conjunto-bebe-nino-3-piezas-rojo-glotoncitos/151988601',330,true),
('e98f9def-123f-51ad-bd5e-03ddab900fb4','luciano-2026','Pack de 3 bodies de manga corta Offcorss para bebé niño','Paquete de tres bodies de manga corta para bebé niño, marca Offcorss.','Ropita','clothes','sage','','https://www.offcorss.com/body-manga-corta-x-3-para-bebe-nino-31202021/p',340,true),
('ef71515d-9d66-50d2-abef-2eb863d00700','luciano-2026','Conjunto largo de dos piezas Offcorss unisex','Conjunto largo de dos piezas para bebé, diseño unisex de Offcorss.','Ropita','clothes','sage','','https://www.offcorss.com/conjunto-largo-dos-piezas-para-bebe-unisex-33120821/p',350,true),
('591f5c42-8e66-5fca-8e51-ffed8128a0e0','luciano-2026','Conjunto de buzo y sudadera Offcorss para bebé niño','Conjunto de dos prendas con buzo y pantalón tipo sudadera para bebé niño.','Ropita','clothes','sage','','https://www.offcorss.com/conjunto-para-bebe-nino-de-buzo-sudadera-31126091/p',360,true),
('d4ed1c70-f7b9-5680-9fe4-4d1f15fbc5b8','luciano-2026','Buzo abierto con capucha Offcorss para bebé niño','Buzo abierto con capucha para bebé niño, marca Offcorss.','Ropita','clothes','sage','','https://www.offcorss.com/buzo-abierto-con-capucha-para-bebe-nino-31135181/p',370,true),
('d2871ab3-b7e0-5d11-bf78-a4f23d030d45','luciano-2026','Monitor de bebé con cámara HelloBaby HB6550','Monitor de video para vigilar al bebé con cámara y pantalla independiente.','Accesorios','bear','sand','','https://www.amazon.com/dp/B09GM8JZM9?th=1',380,true),
('4f26e039-aeaf-5066-abe9-b4a7748ef672','luciano-2026','Nutria relajante Fisher-Price Soothe & Snuggle','Peluche musical de nutria con movimiento suave de respiración, sonidos relajantes y luz para acompañar rutinas de calma.','Accesorios','bear','sand','','https://www.amazon.com/dp/B07N1JP56L?th=1',390,true),
('29dbe1cb-b72e-5d49-89cd-fb4c0d515c45','luciano-2026','Conjunto Pequeño Explorador','Set de 4 piezas para bebé: body estampado, chaqueta acolchada con elefante bordado, pantalón con pie y gorrito a juego.','Ropita','clothes','sage','','https://www.lepetitebaby.com/products/conjunto-dulce-comienzo-copia?variant=42505388294226',400,true),
('4bc4aa7f-27a0-5af6-b83e-bbeb793f064b','luciano-2026','Conjunto Athur','Set de 3 piezas para bebé: body de manga larga con oso bordado, pantalón acolchado y gorrito a juego.','Ropita','clothes','sage','','https://www.lepetitebaby.com/products/jardinera-baby-bloom-boy-copia?variant=42504994979922',410,true)
on conflict(id) do update set
name=excluded.name, description=excluded.description, category=excluded.category,
icon=excluded.icon, color=excluded.color, product_url=excluded.product_url, sort_order=excluded.sort_order,
image_url=coalesce(nullif(excluded.image_url,''),invitation_gifts.image_url);
select category,count(*) as regalos from public.invitation_gifts where event_id='luciano-2026' and enabled group by category order by category;

-- La prueba de asistencia se revierte en una subtransacción; no deja respuestas ficticias.
do $selftest$
declare t1 uuid:=gen_random_uuid(); t2 uuid:=gen_random_uuid();
begin
  begin
    perform public.invitation_save_rsvp('luciano-2026',t1,'Prueba técnica sin correo',true,2,'Prueba temporal');
    perform public.invitation_save_rsvp('luciano-2026',t2,'Prueba técnica sin correo',true,1,'');
    if (select count(*) from public.invitation_rsvps where event_id='luciano-2026' and receipt_token in(t1,t2) and email is null)<>2 then
      raise exception 'Falló la confirmación sin correo.';
    end if;
    perform public.invitation_save_rsvp('luciano-2026',t1,'Prueba técnica sin correo',false,0,'');
    if not exists(select 1 from public.invitation_rsvps where event_id='luciano-2026' and receipt_token=t1 and not attending and party_size=0 and email is null) then
      raise exception 'Falló la actualización de asistencia.';
    end if;
    raise sqlstate 'ZL001';
  exception when sqlstate 'ZL001' then null;
  end;
end;
$selftest$;
do $preserve$
begin
 if (select reserved_ids from luciano_before_update) is distinct from
    (select coalesce(array_agg(gift_id order by gift_id),array[]::uuid[]) from public.invitation_gift_reservations where event_id='luciano-2026') then
   raise exception 'La actualización no debe modificar reservas existentes.';
 end if;
 if (select rsvp_tokens from luciano_before_update) is distinct from
    (select coalesce(array_agg(receipt_token order by receipt_token),array[]::uuid[]) from public.invitation_rsvps where event_id='luciano-2026') then
   raise exception 'La actualización no debe modificar confirmaciones existentes.';
 end if;
 if exists(select 1 from luciano_gift_states b left join public.invitation_gifts g on g.id=b.id where g.id is null or g.enabled is distinct from b.enabled) then
   raise exception 'La actualización no debe cambiar el estado de los regalos anteriores.';
 end if;
 if not has_function_privilege('anon','public.invitation_save_rsvp(text,uuid,text,boolean,integer,text)','EXECUTE')
    or not has_function_privilege('anon','public.invitation_reserve_gift(text,uuid,uuid,text)','EXECUTE') then
   raise exception 'Revisar los permisos de los formularios sin correo.';
 end if;
end;
$preserve$;
select
 (select count(*) from public.invitation_gifts where event_id='luciano-2026') as regalos_totales,
 (select count(*) from public.invitation_available_gifts('luciano-2026')) as regalos_disponibles,
 cardinality(b.reserved_ids) as reservas_anteriores_conservadas,
 cardinality(b.rsvp_tokens) as respuestas_anteriores_conservadas,
 true as asistencia_sin_correo_verificada
from luciano_before_update b;
commit;
