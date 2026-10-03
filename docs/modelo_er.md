# Modelo entidad-relación

```mermaid
erDiagram
    USUARIOS ||--o{ PEDIDOS : realiza
    PEDIDOS ||--|{ DETALLE_PEDIDO : contiene
    PRODUCTOS ||--o{ DETALLE_PEDIDO : aparece_en
    PEDIDOS ||--|| FACTURAS : genera
    PEDIDOS ||--o{ COMPROBANTES_PAGO : recibe
    USUARIOS ||--o{ VERIFICACIONES_EMAIL : verifica

    USUARIOS {
      int id PK
      varchar nombres
      varchar apellidos
      varchar correo UK
      varchar password
      enum rol
      boolean email_verificado
    }
    PRODUCTOS {
      int id PK
      varchar nombre
      int cantidad
      decimal precio
      int tamano_tallo_cm
      varchar imagen_url
    }
    PEDIDOS {
      int id PK
      int usuario_id FK
      decimal total
      varchar estado
      varchar estado_pago
      datetime fecha
    }
    DETALLE_PEDIDO {
      int id PK
      int pedido_id FK
      int producto_id FK
      int cantidad
      decimal precio_unitario
      decimal subtotal
    }
    FACTURAS {
      int id PK
      int pedido_id FK
      varchar numero UK
      decimal total
    }
    COMPROBANTES_PAGO {
      int id PK
      int pedido_id FK
      varchar ruta_archivo
      datetime fecha_subida
    }
    VERIFICACIONES_EMAIL {
      int id PK
      int usuario_id FK
      varchar codigo
      datetime expiracion
      boolean usado
    }
