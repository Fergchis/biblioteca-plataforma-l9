# Red de la biblioteca · L9

Medición de los 17 contenedores activos de Biblioteca con `docker stats --no-stream`, el 12 de noviembre de 2026 a las 11:55:48 UTC, después de la reproducción acreditada en el tramo 3. Las cifras son una instantánea y excluyen el sistema operativo, el motor de contenedores y los procesos sin medición local. El gateway local se usa como referencia para ambas nubes.

## AWS · VPC 10.0.0.0/16 · us-east-1

| Subred | Rango | Zona | Ruta 0.0.0.0/0 |
|---|---|---|---|
| pública | 10.0.1.0/24 | us-east-1a | Internet Gateway |
| aplicación | 10.0.11.0/24 | us-east-1a | interfaz de red de `nat` |
| datos-a | 10.0.21.0/24 | us-east-1a | interfaz de red de `nat` |
| datos-b | 10.0.22.0/24 | us-east-1b | interfaz de red de `nat` |

| Máquina | Subred | IP privada | Tamaño | Lo que corre | Por qué ese tamaño |
|---|---|---|---|---|---|
| `gw-aws` | pública | 10.0.1.20, con Elastic IP | t3.small | Caddy con HTTPS y `biblioteca-gateway` | Gateway 30,69 MiB de 2 GiB. Caddy queda por medir en E2. |
| `nat` | pública | 10.0.1.10 | t3.nano | NAT instance de las subredes privadas | 0,5 GiB para una VM dedicada al reenvío de paquetes, sin contenedores que medir. |
| `servicios` | aplicación | 10.0.11.10 | t3.medium | `biblioteca-libros`, `biblioteca-prestamos` y `biblioteca-eventos` | 22,90 + 63,24 + 72,09 = 158,23 MiB medidos de 4 GiB. Queda margen para el sistema operativo y las variaciones de carga. |
| `gestion` | aplicación | 10.0.11.20 | t3.medium | `biblioteca-admin`, Kafka UI, `biblioteca-simulador`, runner `aws` (Prometheus y Grafana, opcionales) | Admin y Kafka UI sumaron 40,72 + 420,00 = 460,72 MiB de 4 GiB. El simulador, el runner y los opcionales estaban fuera de esta medición. |
| `mq-1` | datos-a | 10.0.21.11 | t3.small | controller 1, broker 4 y `rabbit1` | 266,30 + 592,00 + 134,00 = 992,30 MiB de 2 GiB. |
| `mq-2` | datos-b | 10.0.22.12 | t3.small | controller 2, broker 5 y `rabbit2` | 265,30 + 589,30 + 130,30 = 984,90 MiB de 2 GiB. |
| `mq-3` | datos-a | 10.0.21.13 | t3.small | controller 3 y broker 6 | 291,30 + 606,60 = 897,90 MiB de 2 GiB. |
| `datos` | datos-a | 10.0.21.30 | t3.small | Postgres 18 | Postgres usó 30,18 MiB de 2 GiB en la instantánea. La caché y el uso de memoria pueden crecer con la carga. |

| Grupo de reglas | Puerto | Origen | Para qué |
|---|---|---|---|
| `sg-gw` | 80 | `0.0.0.0/0` | Desafío de Let's Encrypt y redirección a HTTPS |
| `sg-gw` | 443 | pendiente E2 | La API, solo desde la IP pública de `gw-azure` con máscara `/32` |
| `sg-servicios` | 3001, 3002 y 3010 | `sg-gw` y `sg-gestion` | El gateway llega a `libros` y `prestamos` y el administrador revisa `eventos` |
| `sg-mq` | 9092 | `sg-servicios`, `sg-gestion` y `sg-mq` | Clientes de Kafka y réplica entre brokers |
| `sg-mq` | 9093 | `sg-mq` | Quórum KRaft |
| `sg-mq` | 5672 | `sg-servicios` y `sg-gestion` | AMQP de RabbitMQ |
| `sg-mq` | 15672 | `sg-gestion` | Administración de RabbitMQ |
| `sg-mq` | 4369 y 25672 | `sg-mq` | Clúster de RabbitMQ |
| `sg-datos` | 5432 | `sg-servicios` y `sg-gestion` | Postgres |
| `sg-nat` | todos | `sg-servicios`, `sg-gestion`, `sg-mq` y `sg-datos` | Salida a internet de las subredes privadas |
| `sg-gestion` | ninguno | | Acceso por Session Manager |

Las IP privadas son fijas porque los brokers anuncian sus direcciones. Si cae `us-east-1a`, `mq-2` queda en `us-east-1b`, pero pierde el quórum KRaft al quedar un solo controller de tres.

## Azure · VNet 10.1.0.0/16 · `northcentralus`

| Subred | Rango | Salida a internet |
|---|---|---|
| pública | 10.1.1.0/24 | directa, por la IP pública de `gw-azure` |
| privada | 10.1.2.0/24 | por `gw-azure` (tabla de rutas hacia 10.1.1.4), creada con `--default-outbound false` |

| Máquina | Subred | IP privada | Tamaño | Lo que corre | Por qué ese tamaño |
|---|---|---|---|---|---|
| `gw-azure` | pública | 10.1.1.4, con IP pública estática y etiqueta pendiente E2 | B2ats_v2 | Caddy, `biblioteca-web`, `biblioteca-gateway` y NAT de la subred privada | Web y gateway sumaron 13,92 + 30,69 = 44,61 MiB de 1 GiB. Caddy y NAT quedan por medir en E2. |
| `bff` | privada | 10.1.2.4, sin IP pública | B2als_v2 | `biblioteca-bff` y el runner `azure` | BFF usó 32,40 MiB de 4 GiB. Queda memoria para el sistema y el runner, cuyo consumo queda por medir en E2. |

| NSG | Puerto | Origen | Para qué |
|---|---|---|---|
| `gw-azure` | 443 y 80 | Internet | La web y el desafío de Let's Encrypt |
| `gw-azure` | 22 | pendiente E2 | SSH desde la IP de cada integrante con máscara `/32` |
| `gw-azure` | todos | 10.1.2.0/24 | El NAT de `bff` |
| `bff` | todos | 10.1.0.0/16 | Solo desde la VNet |

Capacidades de referencia. [Amazon EC2 T3](https://docs.aws.amazon.com/ec2/latest/instancetypes/gp.html) · [Serie Basv2 de Azure](https://learn.microsoft.com/azure/virtual-machines/sizes/general-purpose/basv2-series)
