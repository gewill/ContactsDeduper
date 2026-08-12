# Política de privacidad

[简体中文](PRIVACY.md) · [繁體中文](PRIVACY.zh-Hant.md) · [English](PRIVACY.en.md) · [日本語](PRIVACY.ja.md) · [한국어](PRIVACY.ko.md) · [Español](PRIVACY.es.md) · [Français](PRIVACY.fr.md) · [Deutsch](PRIVACY.de.md)

Fecha de vigencia: 10 de agosto de 2026

ContactsDeduper es una herramienta de organización de contactos locales para iOS y macOS. Esta política explica cómo la aplicación accede, utiliza y protege los datos de contacto.

## Datos a los que accede la aplicación

Después de otorgar acceso a Contactos, la aplicación puede leer y modificar la siguiente información de contacto:

- Nombres, apodos, organizaciones, departamentos y puestos de trabajo.
- Números de teléfono, direcciones de correo electrónico, URL y direcciones postales
- Cumpleaños, aniversarios y relaciones de contacto.
- Perfiles sociales, cuentas de mensajería instantánea e imágenes de contactos.
- Nombres de listas y grupos y relaciones de membresía en sus cuentas de Contactos

Esta información se utiliza únicamente para encontrar contactos duplicados, mostrar pruebas coincidentes, fusionar contactos y crear o restaurar una copia de seguridad que usted elija explícitamente.

## Recogida y transmisión

- La aplicación no tiene sistema de cuentas, publicidad, análisis, telemetría ni SDK de seguimiento de terceros.
- La aplicación no carga datos de contacto al desarrollador ni a ningún servidor de terceros.
- La aplicación no requiere conexión a la red. La configuración de la zona de pruebas de macOS deshabilita el acceso a la red saliente de forma predeterminada.
- La sincronización de los contactos a través de iCloud, Google u otra cuenta está controlada por la configuración de Contactos del sistema y el proveedor de la cuenta correspondiente, no por la aplicación.

## Archivos de copia de seguridad

Puede exportar contactos explícitamente como un archivo JSON. Una copia de seguridad puede contener números de teléfono confidenciales, direcciones de correo electrónico, direcciones postales, cumpleaños, relaciones, cuentas sociales e imágenes de contactos.

- Los archivos de respaldo se guardan en la ubicación que elija en el selector de archivos del sistema.
- Los archivos de respaldo no se cargan en los servidores del desarrollador.
- El formato de copia de seguridad actual no está cifrado. Guárdelo en una ubicación confiable y no lo comparta públicamente ni lo envíe a un repositorio de Git.
- Durante la importación, la aplicación valida el tamaño del archivo, la versión del formato y el recuento de contactos antes de escribir en Contactos.

## Cambios y eliminación de datos

- Las fusiones masivas y de grupos de contactos únicos modifican la base de datos de contactos del sistema y eliminan los registros duplicados seleccionados para su eliminación.
- La combinación de listas consolida miembros y elimina listas duplicadas dentro de la misma cuenta de Contactos; no elimina contactos como efecto secundario.
- "Eliminar todos los contactos" elimina los contactos actualmente accesibles en la aplicación.
- Todas las acciones destructivas requieren confirmación explícita.
- La aplicación no mantiene una copia en la nube. Exporte una copia de seguridad antes de fusionarla o eliminarla cuando sea posible.

## Controles de permisos

Puede revocar el acceso a Contactos en cualquier momento en la Configuración del sistema iOS o macOS. La aplicación no puede leer ni modificar contactos después de revocar el acceso.

## Actualizaciones de esta política

Si la aplicación agrega servicios de red, análisis, sincronización en la nube o un nuevo uso de datos, esta política se actualizará junto con el código y la versión de lanzamiento.

## Contacto

Si tiene preguntas sobre privacidad, utilice los [GitHub Issues] del proyecto (https://github.com/gewill/ContactsDeduper/issues). No adjunte datos de contacto reales ni archivos de respaldo a un problema.
