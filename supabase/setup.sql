set client_min_messages = warning;
-- ============================================================
-- MANCHESTER FC — SETUP COMPLETO (Supabase SQL Editor)
-- Pegar TODO este archivo en SQL Editor → Run.
-- Es idempotente: se puede volver a ejecutar sin duplicar datos.
-- Si ya habías corrido el schema.sql viejo, lo migra (no borra datos).
-- ============================================================

create extension if not exists pgcrypto;

do $$ begin
  create type public.branch_type as enum ('masculino','femenino');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ledger_type as enum ('income','expense','advance','refund');
exception when duplicate_object then null; end $$;

-- ---------- Limpieza de la versión anterior (roles por enum) ----------
drop view if exists public.player_goal_history;
drop view if exists public.player_totals;
drop function if exists public.can_manage_sports(public.branch_type) cascade;
drop function if exists public.current_role() cascade;

-- ============================================================
-- PLANTELES (squads)
-- ============================================================
create table if not exists public.squads (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  branch public.branch_type not null,
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

insert into public.squads(code,name,branch,sort) values
  ('masculino','Masculino','masculino',1),
  ('fem_1','Femenino · Micaela','femenino',2),
  ('fem_2','Femenino · Agustín','femenino',3)
on conflict (code) do nothing;

-- ============================================================
-- PERFILES Y ROLES
--   admin      → todo + gestión de usuarios (Mateo)
--   organizer  → todo el club: planteles, partidos, finanzas, rifas (Gustavo)
--   coach      → solo su plantel: jugadores, partidos, torneos (Micaela, Agustín)
--   viewer     → cuenta sin autorizar, no ve nada
-- ============================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'viewer',
  created_at timestamptz not null default now()
);
alter table public.profiles alter column role drop default;
alter table public.profiles alter column role type text using role::text;
update public.profiles set role='coach' where role in ('coach_male','coach_female');
alter table public.profiles alter column role set default 'viewer';
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists squad_id uuid references public.squads(id) on delete set null;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','organizer','coach','viewer'));
drop type if exists public.app_role;

-- Personas autorizadas. Es la fuente de verdad de los roles:
-- cuando alguien crea su cuenta con ese email, recibe el rol automáticamente.
create table if not exists public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique,
  role text not null check (role in ('admin','organizer','coach')),
  squad_id uuid references public.squads(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint invite_email_lower check (email is null or email = lower(email))
);

insert into public.staff_invites(full_name,email,role,squad_id)
select v.n, nullif(v.e,''), v.r, (select id from public.squads where code=v.sq)
from (values
  ('Mateo Golfieri','mateogolfieri66@gmail.com','admin',null),
  ('Gustavo','','organizer','masculino'),
  ('Micaela','','coach','fem_1'),
  ('Agustín','','coach','fem_2')
) v(n,e,r,sq)
where not exists (select 1 from public.staff_invites i where i.full_name=v.n);

-- ============================================================
-- TABLAS DEPORTIVAS Y ECONÓMICAS
-- ============================================================
create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  dni text unique,
  pin_hash text,
  full_name text not null,
  branch public.branch_type not null,
  phone text,
  jersey_number integer,
  active boolean not null default true,
  current_debt numeric(12,2) not null default 0 check (current_debt >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_dni check (dni is null or dni ~ '^[0-9]{7,9}$')
);
alter table public.players add column if not exists squad_id uuid references public.squads(id);
alter table public.players add column if not exists pin_set boolean generated always as (pin_hash is not null) stored;

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  season text not null,
  branch public.branch_type not null,
  division text,
  format text not null default 'round_robin',
  direct_promotions integer not null default 0,
  has_playoffs boolean not null default false,
  venue_cost numeric(12,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.tournaments add column if not exists squad_id uuid references public.squads(id);
alter table public.tournaments drop constraint if exists tournaments_name_season_branch_division_key;

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid references public.tournaments(id) on delete set null,
  branch public.branch_type not null,
  match_date date not null,
  opponent text not null,
  stage text not null default 'regular',
  goals_for integer not null default 0,
  goals_against integer not null default 0,
  venue text,
  venue_cost numeric(12,2) not null default 0,
  payer_count integer,
  closed boolean not null default false,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.matches add column if not exists squad_id uuid references public.squads(id);

create table if not exists public.match_players (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  played boolean not null default true,
  starter boolean not null default false,
  goals integer not null default 0 check (goals >= 0),
  assists integer not null default 0 check (assists >= 0),
  yellow_cards integer not null default 0 check (yellow_cards >= 0),
  red_cards integer not null default 0 check (red_cards >= 0),
  amount_due numeric(12,2) not null default 0,
  amount_paid numeric(12,2) not null default 0,
  unique(match_id, player_id)
);

create table if not exists public.ledger (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references public.players(id) on delete set null,
  match_id uuid references public.matches(id) on delete set null,
  entry_date date not null default current_date,
  type public.ledger_type not null,
  category text not null,
  description text,
  amount numeric(12,2) not null check(amount >= 0),
  payment_method text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.fundraising_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  event_type text not null check (event_type in ('raffle','party','tickets','sponsor','other')),
  event_date date,
  goal_amount numeric(12,2) not null default 0,
  raised_amount numeric(12,2) not null default 0,
  expenses_amount numeric(12,2) not null default 0,
  distribution_rule text not null default 'none',
  debt_offset_enabled boolean not null default false,
  status text not null default 'open',
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.fundraising_assignments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.fundraising_events(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  assigned_units integer not null default 0,
  sold_units integer not null default 0,
  collected_amount numeric(12,2) not null default 0,
  pending_amount numeric(12,2) not null default 0,
  credit_generated numeric(12,2) not null default 0,
  unique(event_id, player_id)
);

-- Historial agregado por torneo (torneos viejos sin cargar partido por partido).
create table if not exists public.player_tournament_history (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  tournament_name text not null,
  season text not null,
  division text,
  appearances integer not null default 0,
  goals integer not null default 0,
  yellow_cards integer not null default 0,
  red_cards integer not null default 0,
  provisional boolean not null default false,
  source_note text,
  unique(player_id, tournament_name, season, division)
);

create index if not exists players_squad_idx on public.players(squad_id);
create index if not exists matches_squad_idx on public.matches(squad_id);
create index if not exists tournaments_squad_idx on public.tournaments(squad_id);
create index if not exists match_players_player_idx on public.match_players(player_id);
create index if not exists history_player_idx on public.player_tournament_history(player_id);
create index if not exists profiles_squad_idx on public.profiles(squad_id);
create index if not exists invites_squad_idx on public.staff_invites(squad_id);

-- ============================================================
-- FUNCIONES DE PERMISOS
-- ============================================================
create or replace function public.my_role()
returns text language sql stable security definer set search_path=public
as $$ select coalesce((select role from public.profiles where id=auth.uid()),'none') $$;

create or replace function public.my_squad()
returns uuid language sql stable security definer set search_path=public
as $$ select squad_id from public.profiles where id=auth.uid() $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select public.my_role()='admin' $$;

create or replace function public.is_org()
returns boolean language sql stable security definer set search_path=public
as $$ select public.my_role() in ('admin','organizer') $$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public
as $$ select public.my_role() in ('admin','organizer','coach') $$;

create or replace function public.can_manage_squad(p_squad uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_org() or (public.my_role()='coach' and p_squad is not null and p_squad=public.my_squad()) $$;

-- Plantel por defecto según rama (para datos cargados sin plantel).
create or replace function public.default_squad(p_branch public.branch_type)
returns uuid language sql stable set search_path=public
as $$ select id from public.squads where code = case when p_branch='masculino' then 'masculino' else 'fem_1' end $$;

-- ---------- Triggers: rama sincronizada con el plantel ----------
create or replace function public.sync_squad_branch()
returns trigger language plpgsql set search_path=public
as $$
begin
  if new.squad_id is null then new.squad_id := public.default_squad(new.branch); end if;
  select branch into new.branch from public.squads where id=new.squad_id;
  return new;
end $$;

drop trigger if exists trg_tournaments_squad on public.tournaments;
create trigger trg_tournaments_squad before insert or update on public.tournaments
for each row execute function public.sync_squad_branch();
drop trigger if exists trg_matches_squad on public.matches;
create trigger trg_matches_squad before insert or update on public.matches
for each row execute function public.sync_squad_branch();

-- Jugadores: además protege deuda y PIN (solo organizador/admin o funciones internas).
create or replace function public.players_guard()
returns trigger language plpgsql set search_path=public
as $$
begin
  if new.squad_id is null then new.squad_id := public.default_squad(new.branch); end if;
  select branch into new.branch from public.squads where id=new.squad_id;
  if auth.uid() is not null and not public.is_org()
     and coalesce(current_setting('mfc.bypass',true),'')<>'1' then
    if tg_op='INSERT' then
      new.current_debt := 0;
      new.pin_hash := null;
    else
      new.current_debt := old.current_debt;
      if new.pin_hash is distinct from old.pin_hash then new.pin_hash := old.pin_hash; end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_players_guard on public.players;
create trigger trg_players_guard before insert or update on public.players
for each row execute function public.players_guard();

-- Backfill de planteles para datos existentes
update public.players set squad_id=public.default_squad(branch) where squad_id is null;
update public.tournaments set squad_id=public.default_squad(branch) where squad_id is null;
update public.matches set squad_id=public.default_squad(branch) where squad_id is null;
alter table public.players alter column squad_id set not null;
alter table public.tournaments alter column squad_id set not null;
alter table public.matches alter column squad_id set not null;

-- ============================================================
-- ALTA DE USUARIOS: rol automático según staff_invites
-- ============================================================
create or replace function public.apply_invite(p_user uuid, p_email text)
returns void language plpgsql security definer set search_path=public
as $$
declare inv public.staff_invites;
begin
  if p_user is null then return; end if;
  select * into inv from public.staff_invites where email=lower(p_email);
  insert into public.profiles(id,full_name,email,role,squad_id)
  values(p_user, coalesce(inv.full_name, split_part(p_email,'@',1)), lower(p_email),
         coalesce(inv.role,'viewer'), inv.squad_id)
  on conflict (id) do update
    set full_name=excluded.full_name, email=excluded.email,
        role=case when inv.id is null then 'viewer' else excluded.role end,
        squad_id=excluded.squad_id;
end $$;
revoke all on function public.apply_invite(uuid,text) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$ begin perform public.apply_invite(new.id,new.email); return new; end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Cuando el admin agrega/edita/borra una invitación, se actualiza la cuenta si ya existe.
create or replace function public.invite_sync()
returns trigger language plpgsql security definer set search_path=public
as $$
declare u record;
begin
  if tg_op='DELETE' then
    if old.email is not null then
      update public.profiles set role='viewer', squad_id=null where email=old.email;
    end if;
    return null;
  end if;
  if tg_op='UPDATE' and old.email is not null and new.email is distinct from old.email then
    update public.profiles set role='viewer', squad_id=null where email=old.email;
  end if;
  if new.email is not null then
    for u in select id,email from auth.users where lower(email)=new.email loop
      perform public.apply_invite(u.id,u.email);
    end loop;
  end if;
  return null;
end $$;

create or replace function public.invite_normalize()
returns trigger language plpgsql set search_path=public
as $$ begin new.email := nullif(lower(trim(new.email)),''); return new; end $$;

drop trigger if exists trg_invite_normalize on public.staff_invites;
create trigger trg_invite_normalize before insert or update on public.staff_invites
for each row execute function public.invite_normalize();
drop trigger if exists trg_invite_sync on public.staff_invites;
create trigger trg_invite_sync after insert or update or delete on public.staff_invites
for each row execute function public.invite_sync();

-- La app lo llama al entrar: crea/actualiza el perfil del usuario logueado.
create or replace function public.claim_profile()
returns public.profiles language plpgsql security definer set search_path=public
as $$
declare p public.profiles;
begin
  perform public.apply_invite(auth.uid(), auth.jwt()->>'email');
  select * into p from public.profiles where id=auth.uid();
  return p;
end $$;
revoke all on function public.claim_profile() from public, anon;
grant execute on function public.claim_profile() to authenticated;

-- Cuentas que ya existían antes de correr este setup
do $$ declare u record; begin
  for u in select id,email from auth.users loop perform public.apply_invite(u.id,u.email); end loop;
end $$;

-- ============================================================
-- VISTAS (respetan RLS del usuario)
-- ============================================================
create view public.player_totals with (security_invoker = true) as
select p.id, p.full_name, p.branch, p.squad_id,
  coalesce(m.pj,0)+coalesce(h.pj,0) as matches_played,
  coalesce(m.goals,0)+coalesce(h.goals,0) as goals,
  coalesce(m.yc,0)+coalesce(h.yc,0) as yellow_cards,
  coalesce(m.rc,0)+coalesce(h.rc,0) as red_cards,
  coalesce(m.goals,0) as match_goals,
  coalesce(h.goals,0) as history_goals,
  coalesce(h.provisional,false) as has_provisional
from public.players p
left join (
  select player_id, count(*) filter (where played) pj, sum(goals) goals,
         sum(yellow_cards) yc, sum(red_cards) rc
  from public.match_players group by player_id
) m on m.player_id=p.id
left join (
  select player_id, sum(appearances) pj, sum(goals) goals, sum(yellow_cards) yc,
         sum(red_cards) rc, bool_or(provisional) provisional
  from public.player_tournament_history group by player_id
) h on h.player_id=p.id;

create view public.player_goal_history with (security_invoker = true) as
select p.id as player_id, p.full_name, p.branch, p.squad_id,
  h.tournament_name, h.season, h.division, h.appearances, h.goals,
  h.yellow_cards, h.red_cards, h.provisional,
  sum(case when h.provisional=false then h.goals else 0 end) over(partition by p.id) as verified_goals_total,
  sum(h.goals) over(partition by p.id) as raw_goals_total
from public.players p
join public.player_tournament_history h on h.player_id=p.id;

-- ============================================================
-- FUNCIONES DE NEGOCIO
-- ============================================================
drop function if exists public.player_self_lookup(text,text);
create function public.player_self_lookup(p_dni text,p_pin text)
returns table(full_name text,branch public.branch_type,squad text,current_debt numeric,matches_played bigint,goals bigint,yellow_cards bigint,red_cards bigint)
language sql security definer set search_path=public
as $$
select p.full_name,p.branch,s.name,p.current_debt,
  coalesce((select count(*) from public.match_players mp where mp.player_id=p.id and mp.played),0)
    + coalesce((select sum(appearances) from public.player_tournament_history h where h.player_id=p.id),0),
  coalesce((select sum(goals) from public.match_players mp where mp.player_id=p.id),0)
    + coalesce((select sum(goals) from public.player_tournament_history h where h.player_id=p.id),0),
  coalesce((select sum(yellow_cards) from public.match_players mp where mp.player_id=p.id),0)
    + coalesce((select sum(yellow_cards) from public.player_tournament_history h where h.player_id=p.id),0),
  coalesce((select sum(red_cards) from public.match_players mp where mp.player_id=p.id),0)
    + coalesce((select sum(red_cards) from public.player_tournament_history h where h.player_id=p.id),0)
from public.players p
join public.squads s on s.id=p.squad_id
where p.dni=regexp_replace(p_dni,'\D','','g')
  and p.pin_hash is not null
  and p.pin_hash=crypt(p_pin,p.pin_hash);
$$;
grant execute on function public.player_self_lookup(text,text) to anon, authenticated;

create or replace function public.set_player_pin(p_player_id uuid,p_pin text)
returns void language plpgsql security definer set search_path=public
as $$
declare sq uuid;
begin
  select squad_id into sq from public.players where id=p_player_id;
  if not public.can_manage_squad(sq) then raise exception 'Sin permiso'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN inválido (4 a 8 números)'; end if;
  perform set_config('mfc.bypass','1',true);
  update public.players set pin_hash=crypt(p_pin,gen_salt('bf')) where id=p_player_id;
  perform set_config('mfc.bypass','',true);
end $$;
revoke all on function public.set_player_pin(uuid,text) from public, anon;
grant execute on function public.set_player_pin(uuid,text) to authenticated;

create or replace function public.register_player_payment(p_player_id uuid,p_amount numeric,p_category text default 'Pago jugador',p_method text default null,p_description text default null)
returns numeric language plpgsql security definer set search_path=public
as $$
declare new_debt numeric(12,2);
begin
  if not public.is_org() then raise exception 'Sin permiso'; end if;
  if p_amount<=0 then raise exception 'Monto inválido'; end if;
  update public.players set current_debt=greatest(current_debt-p_amount,0)
  where id=p_player_id returning current_debt into new_debt;
  insert into public.ledger(player_id,type,category,description,amount,payment_method,created_by)
  values(p_player_id,'income',p_category,p_description,p_amount,p_method,auth.uid());
  return new_debt;
end $$;
revoke all on function public.register_player_payment(uuid,numeric,text,text,text) from public, anon;
grant execute on function public.register_player_payment(uuid,numeric,text,text,text) to authenticated;

create or replace function public.close_match(p_match_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare m public.matches; cnt integer; each_due numeric(12,2);
begin
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null then raise exception 'Partido inexistente'; end if;
  if not public.can_manage_squad(m.squad_id) then raise exception 'Sin permiso'; end if;
  if m.closed then return; end if;
  select count(*) into cnt from public.match_players where match_id=p_match_id and played=true;
  if cnt>0 and m.venue_cost>0 then
    each_due:=round(m.venue_cost/cnt,2);
    update public.match_players set amount_due=each_due where match_id=p_match_id and played=true;
    perform set_config('mfc.bypass','1',true);
    update public.players p
    set current_debt=current_debt+greatest(mp.amount_due-mp.amount_paid,0)
    from public.match_players mp
    where mp.match_id=p_match_id and mp.played=true and p.id=mp.player_id;
    perform set_config('mfc.bypass','',true);
  end if;
  update public.matches set closed=true,payer_count=cnt where id=p_match_id;
end $$;
revoke all on function public.close_match(uuid) from public, anon;
grant execute on function public.close_match(uuid) to authenticated;

-- Funciones internas: no se exponen por la API
revoke all on function public.sync_squad_branch() from public, anon, authenticated;
revoke all on function public.players_guard() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.invite_sync() from public, anon, authenticated;
revoke all on function public.invite_normalize() from public, anon, authenticated;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.squads enable row level security;
alter table public.profiles enable row level security;
alter table public.staff_invites enable row level security;
alter table public.players enable row level security;
alter table public.tournaments enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.ledger enable row level security;
alter table public.fundraising_events enable row level security;
alter table public.fundraising_assignments enable row level security;
alter table public.player_tournament_history enable row level security;

drop policy if exists squads_read on public.squads;
create policy squads_read on public.squads for select to authenticated using (public.is_staff());
drop policy if exists squads_admin on public.squads;
create policy squads_admin on public.squads for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());

drop policy if exists invites_admin on public.staff_invites;
create policy invites_admin on public.staff_invites for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists players_staff_read on public.players;
drop policy if exists players_org_write on public.players;
drop policy if exists players_read on public.players;
create policy players_read on public.players for select to authenticated using (public.can_manage_squad(squad_id));
drop policy if exists players_insert on public.players;
create policy players_insert on public.players for insert to authenticated with check (public.can_manage_squad(squad_id));
drop policy if exists players_update on public.players;
create policy players_update on public.players for update to authenticated using (public.can_manage_squad(squad_id)) with check (public.can_manage_squad(squad_id));
drop policy if exists players_delete on public.players;
create policy players_delete on public.players for delete to authenticated using (public.is_org());

drop policy if exists tournaments_read on public.tournaments;
create policy tournaments_read on public.tournaments for select to authenticated using (public.can_manage_squad(squad_id));
drop policy if exists tournaments_write on public.tournaments;
create policy tournaments_write on public.tournaments for all to authenticated using (public.can_manage_squad(squad_id)) with check (public.can_manage_squad(squad_id));

drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select to authenticated using (public.can_manage_squad(squad_id));
drop policy if exists matches_write on public.matches;
create policy matches_write on public.matches for all to authenticated using (public.can_manage_squad(squad_id)) with check (public.can_manage_squad(squad_id));

drop policy if exists match_players_read on public.match_players;
drop policy if exists match_players_write on public.match_players;
create policy match_players_write on public.match_players for all to authenticated
using (exists (select 1 from public.matches m where m.id=match_id and public.can_manage_squad(m.squad_id)))
with check (exists (select 1 from public.matches m where m.id=match_id and public.can_manage_squad(m.squad_id)));

drop policy if exists ledger_org on public.ledger;
create policy ledger_org on public.ledger for all to authenticated using (public.is_org()) with check (public.is_org());

drop policy if exists events_read on public.fundraising_events;
drop policy if exists events_write on public.fundraising_events;
drop policy if exists events_org on public.fundraising_events;
create policy events_org on public.fundraising_events for all to authenticated using (public.is_org()) with check (public.is_org());

drop policy if exists assignments_org on public.fundraising_assignments;
create policy assignments_org on public.fundraising_assignments for all to authenticated using (public.is_org()) with check (public.is_org());

drop policy if exists history_read on public.player_tournament_history;
create policy history_read on public.player_tournament_history for select to authenticated
using (exists (select 1 from public.players p where p.id=player_id and public.can_manage_squad(p.squad_id)));
drop policy if exists history_write on public.player_tournament_history;
create policy history_write on public.player_tournament_history for all to authenticated using (public.is_org()) with check (public.is_org());

-- ============================================================
-- DATOS: TORNEOS 2026
-- ============================================================
insert into public.tournaments(name,season,branch,squad_id,division,format,direct_promotions,has_playoffs,venue_cost,active)
select v.name,'2026',s.branch,s.id,v.division,v.format,v.promo,v.playoffs,v.cost,v.active
from (values
  ('Zona Mixta','masculino','C','round_robin',3,false,74000,false),
  ('Zona Mixta','masculino','B','round_robin',3,false,74000,true),
  ('Zona Mixta','fem_1','A','round_robin',3,false,74000,true),
  ('Landen','masculino',null,'round_robin_playoffs',0,true,64000,true),
  ('Landen','fem_1',null,'round_robin_playoffs',0,true,64000,true)
) v(name,sq,division,format,promo,playoffs,cost,active)
join public.squads s on s.code=v.sq
where not exists (
  select 1 from public.tournaments t
  where t.name=v.name and t.season='2026' and t.squad_id=s.id and coalesce(t.division,'')=coalesce(v.division,'')
);

-- ============================================================
-- DATOS: PLANTELES E HISTORIAL (generado desde data/historial_importado.csv)
-- Femenino se carga en el plantel de Micaela (fem_1). Desde el panel se puede
-- mover cada jugadora al plantel de Agustín (fem_2).
-- ============================================================
insert into public.players(full_name,branch,squad_id)
select v.name, v.branch::public.branch_type, public.default_squad(v.branch::public.branch_type)
from (values
  ('Camino Facundo','masculino'),
  ('Capalbo Franco','masculino'),
  ('Del Pino Gustavo','masculino'),
  ('Fontana Agustin','masculino'),
  ('Gianelli Franco','masculino'),
  ('Golfieri Mateo','masculino'),
  ('Gomez Cristian','masculino'),
  ('Gomez German','masculino'),
  ('Oliva Santiago','masculino'),
  ('Ortiz Mariano','masculino'),
  ('Veliz Alejandro','masculino'),
  ('Villalba Pablo','masculino'),
  ('Zalazar Agustin','masculino'),
  ('Chavez Gonzalo','masculino'),
  ('Maidana Matias','masculino'),
  ('Montana Agus','masculino'),
  ('Florentin Evelyn','femenino'),
  ('Flores Celeste','femenino'),
  ('Flores Micaela','femenino'),
  ('Gonzalez Camila','femenino'),
  ('Larrea Antonella','femenino'),
  ('Maidana Agustina','femenino'),
  ('Marquez Yazmin','femenino'),
  ('Morales Yamila','femenino'),
  ('Peralta Ara','femenino'),
  ('Rea Natalia','femenino'),
  ('Rolon Ticiana','femenino'),
  ('Soto Isabel','femenino'),
  ('Touriño Camil','femenino'),
  ('Velazquez Micaela','femenino'),
  ('Zarco Miriam','femenino')
) v(name,branch)
where not exists (select 1 from public.players p where lower(p.full_name)=lower(v.name));

insert into public.player_tournament_history(player_id,tournament_name,season,division,appearances,goals,yellow_cards,red_cards,provisional,source_note)
select p.id,v.t,v.s,v.d,v.pj,v.g,v.y,v.r,v.prov,v.note
from (values
  ('Camino Facundo','Zona Mixta - Transición','2026','C',7,10,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Capalbo Franco','Zona Mixta - Transición','2026','C',7,1,0,1,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Del Pino Gustavo','Zona Mixta - Transición','2026','C',4,0,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Fontana Agustin','Zona Mixta - Transición','2026','C',4,0,1,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Gianelli Franco','Zona Mixta - Transición','2026','C',5,0,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Golfieri Mateo','Zona Mixta - Transición','2026','C',7,13,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Gomez Cristian','Zona Mixta - Transición','2026','C',5,2,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Gomez German','Zona Mixta - Transición','2026','C',7,7,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Oliva Santiago','Zona Mixta - Transición','2026','C',7,1,1,1,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Ortiz Mariano','Zona Mixta - Transición','2026','C',6,2,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Veliz Alejandro','Zona Mixta - Transición','2026','C',7,2,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Villalba Pablo','Zona Mixta - Transición','2026','C',7,0,0,0,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Zalazar Agustin','Zona Mixta - Transición','2026','C',7,0,0,1,false,'Capturas del plantel. Equipo: 9 PJ, 44 GF, 18 GC. Goles asignables por jugador: 38.'),
  ('Camino Facundo','Zona Mixta - Clausura','2026','B',6,7,1,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Capalbo Franco','Zona Mixta - Clausura','2026','B',5,1,1,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Chavez Gonzalo','Zona Mixta - Clausura','2026','B',4,0,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Del Pino Gustavo','Zona Mixta - Clausura','2026','B',5,1,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Gianelli Franco','Zona Mixta - Clausura','2026','B',6,1,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Golfieri Mateo','Zona Mixta - Clausura','2026','B',6,5,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Gomez Cristian','Zona Mixta - Clausura','2026','B',7,1,1,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Gomez German','Zona Mixta - Clausura','2026','B',6,2,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Maidana Matias','Zona Mixta - Clausura','2026','B',7,3,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Montana Agus','Zona Mixta - Clausura','2026','B',7,3,2,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Oliva Santiago','Zona Mixta - Clausura','2026','B',6,8,2,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Ortiz Mariano','Zona Mixta - Clausura','2026','B',6,0,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Veliz Alejandro','Zona Mixta - Clausura','2026','B',6,0,0,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Zalazar Agustin','Zona Mixta - Clausura','2026','B',6,0,1,0,false,'Capturas del plantel. Equipo: 7 PJ, 32 GF, 19 GC.'),
  ('Florentin Evelyn','Zona Mixta - snapshot femenino','2026','A',6,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Flores Celeste','Zona Mixta - snapshot femenino','2026','A',6,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Flores Micaela','Zona Mixta - snapshot femenino','2026','A',8,1,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Gonzalez Camila','Zona Mixta - snapshot femenino','2026','A',6,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Larrea Antonella','Zona Mixta - snapshot femenino','2026','A',5,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Maidana Agustina','Zona Mixta - snapshot femenino','2026','A',6,1,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Marquez Yazmin','Zona Mixta - snapshot femenino','2026','A',5,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Morales Yamila','Zona Mixta - snapshot femenino','2026','A',6,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Peralta Ara','Zona Mixta - snapshot femenino','2026','A',6,0,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Rea Natalia','Zona Mixta - snapshot femenino','2026','A',8,4,1,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Rolon Ticiana','Zona Mixta - snapshot femenino','2026','A',8,4,1,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Soto Isabel','Zona Mixta - snapshot femenino','2026','A',6,3,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Touriño Camil','Zona Mixta - snapshot femenino','2026','A',6,0,0,1,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Velazquez Micaela','Zona Mixta - snapshot femenino','2026','A',8,4,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.'),
  ('Zarco Miriam','Zona Mixta - snapshot femenino','2026','A',6,2,0,0,true,'Mismos valores en capturas de Transición y Clausura; requiere confirmación antes de asignar por torneo.')
) v(name,t,s,d,pj,g,y,r,prov,note)
join public.players p on lower(p.full_name)=lower(v.name)
on conflict (player_id,tournament_name,season,division) do update
set appearances=excluded.appearances, goals=excluded.goals, yellow_cards=excluded.yellow_cards,
    red_cards=excluded.red_cards, provisional=excluded.provisional, source_note=excluded.source_note;

-- Verificación rápida (debería mostrar Golfieri Mateo 18, Camino Facundo 17, Oliva Santiago 9...):
-- select full_name, goals, matches_played from public.player_totals order by goals desc limit 10;
