from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle


def generar_comprobante_pdf(pedido, detalles):
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=40, leftMargin=40, topMargin=40, bottomMargin=40)
    styles = getSampleStyleSheet()
    story = [
        Paragraph("FLORÍCOLA LOS ÁLAMOS", styles["Title"]),
        Paragraph("COMPROBANTE DE COMPRA", styles["Heading2"]),
        Spacer(1, 10),
        Paragraph(f"N.º: {pedido.get('numero') or pedido['id']}", styles["Normal"]),
        Paragraph(f"Fecha: {pedido['fecha']}", styles["Normal"]),
        Paragraph(f"Cliente: {pedido['nombres']} {pedido['apellidos']}", styles["Normal"]),
        Paragraph(f"Correo: {pedido['correo']}", styles["Normal"]),
        Spacer(1, 15),
    ]
    data = [["Producto", "Cantidad", "Precio", "Subtotal"]]
    for d in detalles:
        data.append([d["nombre"], str(d["cantidad"]), f"${float(d['precio_unitario']):.2f}", f"${float(d['subtotal']):.2f}"])
    data.append(["", "", "TOTAL", f"${float(pedido['total']):.2f}"])
    table = Table(data, colWidths=[250, 70, 70, 80])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (-2, -1), (-1, -1), "Helvetica-Bold"),
        ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.extend([table, Spacer(1, 15), Paragraph("Forma de pago: transferencia bancaria", styles["Normal"]), Paragraph("Estado del pago: confirmado", styles["Normal"]), Spacer(1, 10), Paragraph("Este documento es un comprobante de compra generado por la aplicación y no constituye una factura electrónica tributaria.", styles["Italic"])])
    doc.build(story)
    return buffer.getvalue()
