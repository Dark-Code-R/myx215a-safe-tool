# Guía de uso de MYX Menu

Herramienta automática para quitar el login/kiosco de MYX Fitness en una MYX215A.

## Qué hace

- Respaldar el APK MDM y sus políticas.
- Hacer un respaldo completo opcional.
- Desactivar `MDMMYX.apk` de forma reversible.
- Eliminar la política `Device Owner`.
- Reiniciar y verificar el launcher normal.

Este proceso **no desbloquea el bootloader**. El bootloader permanece bloqueado.

## Requisitos

- Ubuntu/Linux.
- `adb` instalado.
- Una sola MYX conectada por USB.
- MYX215A encendida y dentro de Android.
- Pantalla desbloqueada y encendida.
- Depuración USB activa.
- La compilación debe permitir `adb root`.

## Antes de comenzar

1. Encender la MYX.
2. Esperar a que inicie Android.
3. Desbloquear la pantalla.
4. No conectar Wi-Fi todavía.
5. Conectar el cable USB.
6. Mantener la pantalla encendida.
7. No desconectar el cable durante el proceso.

No usar fastboot, `wipe`, `erase`, `format` ni `unlock`. El programa no modifica `NVRAM`, `NVDATA`, `userdata`, `preloader`, `proinfo` ni `seccfg`.

## Iniciar el menú

```bash
cd /run/media/rodrigo555a/MYX_DATA/MYX/myx_automation
./myx_menu.sh
```

El menú detecta automáticamente el serial, modelo, Android y build.

## Opciones del menú

### Opción 1: Respaldo pequeño

Respaldar antes de modificar. Guarda:

- `MDMMYX.apk` original.
- `device_owner_2.xml`.
- `device_policies.xml`.
- `users/0.xml`.
- Información del dispositivo.

Esta opción es obligatoria antes de elegir la opción 3.

### Opción 2: Respaldo completo

Lee las particiones mediante ADB y verifica sus tamaños. Necesita varios GB libres.

Omite intencionadamente `userdata` y `rpmb`.

Es recomendable, pero opcional si no hay espacio suficiente.

### Opción 3: Quitar login/MDM

Es la opción principal. Antes de confirmarla, la pantalla debe estar encendida, desbloqueada y sin Wi-Fi.

Al confirmar con `s`, el programa:

1. Ejecuta `disable-verity`.
2. Reinicia la MYX.
3. Ejecuta `adb root` y `remount`.
4. Guarda otra copia del APK MDM.
5. Renombra `MDMMYX.apk` a `MDMMYX.apk.disabled`.
6. Limpia `Device Owner` y las políticas de kiosco.
7. Reinicia la MYX.
8. Guarda los registros de resultado.

Después debería aparecer el launcher normal sin el login de MYX.

### Opción 4: Verificar estado

Muestra:

- Identidad ADB root.
- Ruta del APK MDM.
- Estado de `Device Owner`.
- Restricciones de kiosco y barra de estado.

Debe ejecutarse antes de modificar y nuevamente después de la opción 3.

Después de la modificación no debería aparecer `com.abupdate.mdm`, `lock-task` ni `statusbar disabled`.

### Opción 5: Volver a detectar dispositivo

Se utiliza cuando se desconecta una MYX y se conecta otra, o cuando se cambia de pantalla. El menú vuelve a detectar el serial y la información del dispositivo.

## Orden recomendado

Para una MYX nueva:

```text
4 → verificar
1 → respaldo pequeño
2 → respaldo completo opcional
3 → quitar login/MDM
4 → verificar resultado
```

Usar la opción `5` solamente cuando se cambie de dispositivo.

## Ubicación de los respaldos

El menú crea carpetas separadas por serial y fecha dentro de:

```text
myx_automation/backups/
```

Nunca mezclar respaldos de diferentes MYX215A.

## Si algo falla

No desconectar inmediatamente si el programa está reiniciando. Esperar a que termine y leer el error.

El APK MDM original queda guardado tanto en el respaldo del ordenador como dentro de:

```text
/data/local/tmp/MDMMYX.apk.original
```

La restauración debe hacerse únicamente usando el respaldo correspondiente al mismo número de serie.
