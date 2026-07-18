# Finora

Aplicacion de finanzas personales **offline-first** para Android, construida con Flutter.
Permite registrar cuentas, tarjetas de credito, transacciones y metas de ahorro sin necesitar
conexion a internet, sincronizando automaticamente con Supabase cuando el dispositivo recupera
conectividad. Incluye bloqueo biometrico (huella) para proteger el acceso a la app.

## Caracteristicas principales

- **Offline-first**: toda la operacion diaria (agregar gastos/ingresos, cuentas, tarjetas,
  metas) funciona sin conexion gracias a una base de datos local (Drift/SQLite).
- **Sincronizacion multi-dispositivo**: al reconectar, los cambios se suben/descargan contra
  Supabase. Los conflictos se resuelven con **Last-Write-Wins (LWW)** por marca de tiempo,
  evitando duplicados.
- **Bloqueo biometrico**: acceso protegido con huella digital mediante `local_auth`.
- **Dashboard**: saldo total, ingresos/gastos/ahorro del mes.
- **Tarjetas de credito**: seguimiento de linea usada/disponible y fecha de pago, con
  notificaciones locales antes del vencimiento y alertas al 90%/100% del limite mensual.
- **Estadisticas**: grafico donut de gastos por categoria y evolucion de los ultimos 6 meses.
- **Calendario**: proximos vencimientos de tarjetas.
- **Metas de ahorro**: seguimiento de progreso hacia objetivos definidos por el usuario.

## Stack tecnico

- **Flutter** (Dart) — UI multiplataforma (target: Android).
- **Riverpod** (`flutter_riverpod`) — gestion de estado.
- **go_router** — navegacion declarativa.
- **Drift** (`drift`, `drift_flutter`) — base de datos local SQLite tipada.
- **Supabase** (`supabase_flutter`) — backend remoto (autenticacion + Postgres) y motor de
  sincronizacion.
- **local_auth** — autenticacion biometrica (huella).
- **flutter_local_notifications** + **timezone** — notificaciones locales programadas.
- **fl_chart** — graficos (donut y barras).
- **connectivity_plus** — deteccion de estado de red para disparar sincronizacion.
- **google_fonts**, **intl**, **uuid** — utilidades de UI/formato/identificadores.

## Requisitos previos

- Flutter SDK (canal estable, compatible con `sdk: ^3.12.2` de Dart, ver `pubspec.yaml`).
- Un proyecto de Supabase (URL + anon key).
- Android Studio / SDK de Android para compilar el APK.

## Configuracion del entorno

1. Instalar dependencias:

   ```bash
   flutter pub get
   ```

2. Copiar el archivo de variables de entorno de ejemplo y completar las credenciales de
   Supabase:

   ```bash
   cp env.example.json env.json
   ```

   Editar `env.json` con los valores reales del proyecto de Supabase:

   ```json
   {
     "SUPABASE_URL": "https://tu-proyecto-ref.supabase.co",
     "SUPABASE_ANON_KEY": "tu-anon-key"
   }
   ```

   `env.json` esta en `.gitignore` y nunca debe subirse al repositorio.

## Ejecutar en desarrollo

```bash
flutter run --dart-define-from-file=env.json
```

## Ejecutar tests

```bash
flutter test
```

Analisis estatico (debe estar limpio antes de cualquier build de release):

```bash
flutter analyze
```

## Build de release (APK firmado)

```bash
flutter build apk --release --dart-define-from-file=env.json
```

El APK firmado queda en `build/app/outputs/flutter-apk/app-release.apk`.

### Nota sobre el keystore de firma

El build de release firma el APK usando un keystore Java (`.jks`) que **vive fuera del
repositorio** y un archivo `android/key.properties` (gitignorado) que referencia su
ubicacion y contraseñas. Ninguno de los dos se versiona con git.

- **Sin el keystore original no es posible publicar actualizaciones de la app** bajo el
  mismo `applicationId`/firma: Android rechaza instalar una actualizacion firmada con una
  clave distinta a la original. Perder el keystore equivale a perder la identidad de la
  aplicacion (no se podria actualizar una instalacion existente ni la ficha de Play Store
  si se llegara a publicar ahi).
- **Hacer backup inmediatamente** del archivo `.jks` y de las contraseñas (`storePassword`,
  `keyPassword`) en un gestor de contraseñas o almacenamiento seguro, en al menos dos
  ubicaciones distintas.
- Si se necesita regenerar `android/key.properties` en una maquina nueva, usar el formato:

  ```properties
  storePassword=<password>
  keyPassword=<password>
  keyAlias=finora
  storeFile=<ruta-absoluta-al-.jks>
  ```
