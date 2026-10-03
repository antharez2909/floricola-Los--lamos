# Flujo de compra y pago

```mermaid
sequenceDiagram
    participant U as Cliente
    participant F as Flutter
    participant API as Flask API
    participant DB as MySQL
    participant A as Administrador
    participant SMTP as Correo

    U->>F: Agrega productos
    F->>F: Persiste carrito local
    U->>F: Confirmar pedido
    F->>API: POST /api/pedidos
    API->>DB: BEGIN + SELECT ... FOR UPDATE
    API->>DB: Insertar pedido/detalle/factura
    API->>DB: Descontar stock
    DB-->>API: COMMIT
    API-->>F: Pedido creado
    U->>F: Sube comprobante
    F->>API: POST /api/pedidos/{id}/comprobante
    API->>DB: Guardar comprobante + estado en_revision
    A->>API: Revisar pago
    API->>DB: Bloquear pedido y verificar en_revision
    API->>DB: Confirmar o rechazar
    alt Confirmado
        API->>SMTP: Enviar PDF
        SMTP-->>U: Comprobante de compra
    end
    API-->>A: Resultado de revisión
