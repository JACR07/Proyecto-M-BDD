SET search_path TO hotel_reservas;

-- 1. Habitaciones disponibles en un rango de fechas.
SELECT
    h.id_habitacion,
    ho.nombre AS hotel,
    h.numero,
    th.nombre AS tipo_habitacion,
    th.capacidad,
    th.precio_noche
FROM habitacion h
JOIN hotel ho ON ho.id_hotel = h.id_hotel
JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
WHERE h.estado = 'DISPONIBLE'
  AND NOT EXISTS (
      SELECT 1
      FROM reserva r
      WHERE r.id_habitacion = h.id_habitacion
        AND r.estado IN ('CONFIRMADA', 'CHECK_IN')
        AND daterange(r.fecha_inicio, r.fecha_fin, '[)')
            && daterange(DATE '2026-01-10', DATE '2026-01-14', '[)')
  )
ORDER BY ho.nombre, h.numero;

-- 2. Huespedes con mayor gasto historico.
SELECT
    hu.id_huesped,
    hu.nombres || ' ' || hu.apellidos AS huesped,
    COUNT(f.id_factura) AS facturas_emitidas,
    SUM(f.total) AS gasto_total
FROM huesped hu
JOIN reserva r ON r.id_huesped = hu.id_huesped
JOIN estancia e ON e.id_reserva = r.id_reserva
JOIN factura f ON f.id_estancia = e.id_estancia
GROUP BY hu.id_huesped, hu.nombres, hu.apellidos
ORDER BY gasto_total DESC
LIMIT 10;

-- 3. Servicios mas consumidos por tipo de habitacion.
SELECT
    th.nombre AS tipo_habitacion,
    s.categoria,
    s.nombre AS servicio,
    SUM(cs.cantidad) AS cantidad_consumida,
    SUM(cs.total) AS total_generado
FROM consumo_servicio cs
JOIN servicio s ON s.id_servicio = cs.id_servicio
JOIN estancia e ON e.id_estancia = cs.id_estancia
JOIN reserva r ON r.id_reserva = e.id_reserva
JOIN habitacion h ON h.id_habitacion = r.id_habitacion
JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
GROUP BY th.nombre, s.categoria, s.nombre
ORDER BY th.nombre, cantidad_consumida DESC;

-- 4. Tasa de ocupacion por tipo de habitacion.
SELECT
    th.nombre AS tipo_habitacion,
    COUNT(DISTINCT h.id_habitacion) AS total_habitaciones,
    COUNT(DISTINCT r.id_reserva) FILTER (
        WHERE r.estado IN ('CONFIRMADA', 'CHECK_IN', 'FINALIZADA')
    ) AS reservas_validas,
    ROUND(
        COUNT(DISTINCT r.id_reserva) FILTER (
            WHERE r.estado IN ('CONFIRMADA', 'CHECK_IN', 'FINALIZADA')
        )::NUMERIC / NULLIF(COUNT(DISTINCT h.id_habitacion), 0),
        2
    ) AS reservas_por_habitacion
FROM tipo_habitacion th
JOIN habitacion h ON h.id_tipo_habitacion = th.id_tipo_habitacion
LEFT JOIN reserva r ON r.id_habitacion = h.id_habitacion
GROUP BY th.nombre
ORDER BY reservas_por_habitacion DESC;

-- 5. Ingresos totales por mes en el anio actual en curso.
SELECT
    TO_CHAR(f.fecha_emision, 'YYYY-MM') AS mes,
    COUNT(f.id_factura) AS total_facturas,
    SUM(f.subtotal_habitacion) AS ingresos_habitacion,
    SUM(f.subtotal_servicios) AS ingresos_servicios,
    SUM(f.impuestos) AS impuestos,
    SUM(f.total) AS ingresos_totales
FROM factura f
GROUP BY TO_CHAR(f.fecha_emision, 'YYYY-MM')
ORDER BY mes;


-- 6. Busqueda textual de huespedes por correo o nombre.
SELECT
    id_huesped,
    UPPER(nombres || ' ' || apellidos) AS huesped,
    email,
    telefono
FROM huesped
WHERE LOWER(email) LIKE '%huesped1%'
   OR LOWER(nombres || ' ' || apellidos) LIKE '%huesped1%'
ORDER BY huesped;

-- 7. Reservas proximas usando funciones de fecha.
SELECT
    r.codigo_reserva,
    hu.nombres || ' ' || hu.apellidos AS huesped,
    h.numero AS habitacion,
    r.fecha_inicio,
    r.fecha_fin,
    r.fecha_inicio - CURRENT_DATE AS dias_para_llegada
FROM reserva r
JOIN huesped hu ON hu.id_huesped = r.id_huesped
JOIN habitacion h ON h.id_habitacion = r.id_habitacion
WHERE r.estado = 'CONFIRMADA'
ORDER BY r.fecha_inicio
LIMIT 15;
