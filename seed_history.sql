-- MANCHESTER FC — seed histórico
-- Ejecutar DESPUÉS de schema.sql.
-- DNI queda NULL: el organizador los completa luego.

insert into public.tournaments(name,season,branch,division,format,direct_promotions,has_playoffs,venue_cost,active)
values
('Zona Mixta','2026','masculino','C','round_robin',3,false,74000,false),
('Zona Mixta','2026','masculino','B','round_robin',3,false,74000,true),
('Zona Mixta','2026','femenino','A','round_robin',3,false,74000,true),
('Landen','2026','masculino',null,'round_robin_playoffs',0,true,64000,true),
('Landen','2026','femenino',null,'round_robin_playoffs',0,true,64000,true)
on conflict do nothing;

-- Jugadores masculinos (unión de los dos planteles vistos)
insert into public.players(full_name,branch)
select v.name,'masculino'::public.branch_type
from (values
('Camino Facundo'),('Capalbo Franco'),('Chavez Gonzalo'),('Del Pino Gustavo'),
('Fontana Agustin'),('Gianelli Franco'),('Golfieri Mateo'),('Gomez Cristian'),
('Gomez German'),('Maidana Matias'),('Montana Agus'),('Oliva Santiago'),
('Ortiz Mariano'),('Veliz Alejandro'),('Villalba Pablo'),('Zalazar Agustin')
) v(name)
where not exists(select 1 from public.players p where lower(p.full_name)=lower(v.name));

-- Jugadoras femeninas (plantel visible)
insert into public.players(full_name,branch)
select v.name,'femenino'::public.branch_type
from (values
('Florentin Evelyn'),('Flores Celeste'),('Flores Micaela'),('Gonzalez Camila'),
('Larrea Antonella'),('Maidana Agustina'),('Marquez Yazmin'),('Morales Yamila'),
('Peralta Ara'),('Rea Natalia'),('Rolon Ticiana'),('Soto Isabel'),
('Touriño Camil'),('Velazquez Micaela'),('Zarco Miriam')
) v(name)
where not exists(select 1 from public.players p where lower(p.full_name)=lower(v.name));

-- Masculino Transición 2026 División C.
-- El equipo figura con 44 GF, pero la suma de goles individualmente visibles da 38.
-- Guardamos exactamente lo asignable por jugador y dejamos la diferencia documentada.
with s(name,app,g,y,r) as (values
('Camino Facundo',7,10,0,0),
('Capalbo Franco',7,1,0,1),
('Del Pino Gustavo',4,0,0,0),
('Fontana Agustin',4,0,1,0),
('Gianelli Franco',5,0,0,0),
('Golfieri Mateo',7,13,0,0),
('Gomez Cristian',5,2,0,0),
('Gomez German',7,7,0,0),
('Oliva Santiago',7,1,1,1),
('Ortiz Mariano',6,2,0,0),
('Veliz Alejandro',7,2,0,0),
('Villalba Pablo',7,0,0,0),
('Zalazar Agustin',7,0,0,1)
)
insert into public.player_tournament_history(player_id,tournament_name,season,division,appearances,goals,yellow_cards,red_cards,provisional,source_note)
select p.id,'Zona Mixta - Transición','2026','C',s.app,s.g,s.y,s.r,false,
'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'
from s join public.players p on lower(p.full_name)=lower(s.name)
on conflict do nothing;

-- Masculino Clausura 2026 División B actual.
-- Los goles individuales suman 32, igual al GF del equipo en la captura.
with s(name,app,g,y,r) as (values
('Camino Facundo',6,7,1,0),
('Capalbo Franco',5,1,1,0),
('Chavez Gonzalo',4,0,0,0),
('Del Pino Gustavo',5,1,0,0),
('Gianelli Franco',6,1,0,0),
('Golfieri Mateo',6,5,0,0),
('Gomez Cristian',7,1,1,0),
('Gomez German',6,2,0,0),
('Maidana Matias',7,3,0,0),
('Montana Agus',7,3,2,0),
('Oliva Santiago',6,8,2,0),
('Ortiz Mariano',6,0,0,0),
('Veliz Alejandro',6,0,0,0),
('Zalazar Agustin',6,0,1,0)
)
insert into public.player_tournament_history(player_id,tournament_name,season,division,appearances,goals,yellow_cards,red_cards,provisional,source_note)
select p.id,'Zona Mixta - Clausura','2026','B',s.app,s.g,s.y,s.r,false,
'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'
from s join public.players p on lower(p.full_name)=lower(s.name)
on conflict do nothing;

-- Femenino: las dos capturas de plantel muestran exactamente la misma estadística individual.
-- Además hay jugadoras con 8 apariciones aunque una tabla muestra 7 PJ y la otra 4 PJ.
-- Por eso NO duplicamos esos goles como dos torneos distintos: se importa un snapshot provisional
-- para evitar inflar el total histórico hasta que el organizador confirme a qué torneo pertenecen.
with s(name,app,g,y,r) as (values
('Florentin Evelyn',6,0,0,0),
('Flores Celeste',6,0,0,0),
('Flores Micaela',8,1,0,0),
('Gonzalez Camila',6,0,0,0),
('Larrea Antonella',5,0,0,0),
('Maidana Agustina',6,1,0,0),
('Marquez Yazmin',5,0,0,0),
('Morales Yamila',6,0,0,0),
('Peralta Ara',6,0,0,0),
('Rea Natalia',8,4,1,0),
('Rolon Ticiana',8,4,1,0),
('Soto Isabel',6,3,0,0),
('Touriño Camil',6,0,0,1),
('Velazquez Micaela',8,4,0,0),
('Zarco Miriam',6,2,0,0)
)
insert into public.player_tournament_history(player_id,tournament_name,season,division,appearances,goals,yellow_cards,red_cards,provisional,source_note)
select p.id,'Zona Mixta - snapshot femenino','2026','A',s.app,s.g,s.y,s.r,true,
'Los mismos valores aparecen bajo las capturas de Transición y Clausura; requiere confirmación del organizador antes de asignar por torneo.'
from s join public.players p on lower(p.full_name)=lower(s.name)
on conflict do nothing;

-- Vista rápida de goleadores históricos masculinos verificados:
-- select full_name,tournament_name,goals,verified_goals_total
-- from public.player_goal_history
-- where branch='masculino'
-- order by verified_goals_total desc, full_name;
