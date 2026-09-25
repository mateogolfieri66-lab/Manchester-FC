# Manchester F.C. — Gestión del Club

App web (un solo `index.html`) con Supabase de base de datos. Se publica en Vercel tal cual, sin build.

## Puesta en marcha

1. **Base de datos**: en Supabase → *SQL Editor* → pegar todo `supabase/setup.sql` → *Run*.
   Crea tablas, permisos, planteles, torneos 2026 y el historial de goles (`data/historial_importado.csv`).
   Se puede volver a ejecutar sin duplicar nada.
2. **Auth**: en Supabase → *Authentication → URL Configuration* poné en *Site URL* la URL de Vercel
   (así funcionan los emails de confirmación y de "olvidé mi contraseña").
3. **Primer ingreso (Mateo)**: en la app, *Crear mi cuenta* con `mateogolfieri66@gmail.com` → queda como Administrador.
4. **Resto del staff**: en *Usuarios* completá el email de Gustavo, Micaela y Agustín y guardá.
   Cada uno entra a la app, toca *Crear mi cuenta* con ese email y recibe su rol automáticamente.

## Roles

| Persona | Rol | Ve y gestiona |
|---|---|---|
| Mateo | Administrador | Todo + usuarios, permisos y planteles |
| Gustavo | Organizador (plantel Masculino) | Todo el club: planteles, partidos, finanzas, rifas |
| Micaela | DT · Femenino · Micaela | Solo su plantel: jugadoras, partidos, torneos |
| Agustín | DT · Femenino · Agustín | Solo su plantel: jugadoras, partidos, torneos |

Los permisos se aplican en la base de datos (RLS), no solo en la pantalla.
Un DT no ve finanzas ni deudas, y no puede tocar la deuda ni otros planteles.

## Jugadores

- Las jugadoras del historial se cargaron en el plantel de Micaela. Para pasar alguna al de Agustín:
  *Plantel* → tocar la jugadora → cambiar *Plantel* → Guardar.
- Cargando DNI + PIN, cada jugador/a consulta su deuda y estadísticas en la pestaña *Jugador/a* del login.
- Los goles del femenino importados están marcados como provisorios (`*`) porque las capturas no
  permitían saber a qué torneo correspondían.
