# Casos de uso principales

```mermaid
flowchart TB
    Cliente((Cliente))
    Admin((Administrador))

    Cliente --> R[Registrarse]
    Cliente --> V[Verificar correo]
    Cliente --> L[Iniciar sesión]
    Cliente --> P[Consultar productos]
    Cliente --> C[Gestionar carrito]
    Cliente --> CP[Crear pedido]
    Cliente --> T[Subir comprobante]
    Cliente --> H[Consultar historial]

    Admin --> AL[Iniciar sesión]
    Admin --> AP[Gestionar productos]
    Admin --> AC[Consultar clientes]
    Admin --> AO[Gestionar pedidos]
    Admin --> RP[Revisar pago]
    RP --> CONF[Confirmar o rechazar pago]
    CONF --> PDF[Generar y enviar comprobante PDF]
