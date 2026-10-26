# Reglas del dominio

## Asistencia

El porcentaje es `100 × presentes / (presentes + ausentes)`. Sin denominador se muestra «—», no 0 %. Se excluyen pendientes, excusados, eventos en borrador o cancelados y eventos que no cuentan para asistencia. Solo se examinan eventos en cuya lista figura la persona; un registro sin marcar queda pendiente.

Los filtros de período, grupo, componente, categoría y evento se aplican antes del cálculo. La pertenencia al grupo se comprueba en la fecha del evento, con límites inclusivos. Los totales se calculan a partir de registros; nunca promedian porcentajes redondeados. El desglose individual incluye el total, cada componente, sus categorías y los eventos sin categoría.

## Voluntariado

El flujo es interesado → seleccionado → completado, declinado o ausente. Las validaciones de estado y capacidad se aplican antes de guardar. La selección final es manual.

La puntuación es `3 × voluntariados completados anteriores + asistencias presentes anteriores`. Se consideran eventos anteriores elegibles; las asistencias requieren que el evento cuente y que la persona esté en su lista. Solo se sugieren registros interesados del evento actual. Los empates se ordenan por nombre y después identificador. La interfaz muestra el estado activo de la persona y los motivos de puntuación.

## Integridad y recuperación

Cada espacio contiene sus propios registros. Se validan referencias, fechas, capacidades y transiciones. Los cambios producen revisiones; deshacer y rehacer conservan ese historial. La importación valida JSON v1. Los conflictos mantienen ambas versiones hasta su resolución explícita.

La persistencia usa escritura atómica, bloqueo entre procesos y comprobación de la versión leída. Se conserva una copia anterior recuperable. La recuperación mantiene el archivo que sustituye. El intercambio entre usuarios se realiza mediante archivos exportados; no hay sincronización automática de red.
