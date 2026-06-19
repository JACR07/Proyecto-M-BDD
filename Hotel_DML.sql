SET search_path TO hotel_reservas;

-- Hoteles 
INSERT INTO hotel (nombre, direccion, ciudad, telefono, email, estrellas) VALUES
('Hotel Brisas del Pacifico', 'Boulevard Costa Azul #120', 'La Libertad', '2222-0101', 'reservas@brisas.com', 5);

-- Tipos de habitacion
INSERT INTO tipo_habitacion (nombre, descripcion, capacidad, precio_noche) VALUES
('Individual', 'Habitacion para una persona con cama individual.', 1, 55.00),
('Doble', 'Habitacion para dos personas con dos camas o cama matrimonial.', 2, 85.00),
('Familiar', 'Habitacion amplia para familias pequenas.', 4, 130.00),
('Suite', 'Habitacion premium con sala privada y vista especial.', 3, 210.00);

-- Habitaciones: 60 habitaciones asociadas obligatoriamente al hotel (12 por piso, 5 pisos).
INSERT INTO habitacion (id_hotel, id_tipo_habitacion, numero, piso, estado)
SELECT
    1 AS id_hotel,
    CASE
        WHEN gs % 10 IN (1, 2, 3) THEN 1
        WHEN gs % 10 IN (4, 5, 6) THEN 2
        WHEN gs % 10 IN (7, 8) THEN 3
        ELSE 4
    END AS id_tipo_habitacion,
    (((gs - 1) / 12) + 1)::TEXT || LPAD((((gs - 1) % 12) + 1)::TEXT, 2, '0') AS numero,
    ((gs - 1) / 12) + 1 AS piso,
    'DISPONIBLE'
FROM generate_series(1, 60) AS gs;

-- Huespedes
INSERT INTO huesped (nombres, apellidos, documento, email, telefono, fecha_registro)
SELECT
    'Huesped' || gs,
    'Apellido' || gs,
    'DOC-' || LPAD(gs::TEXT, 5, '0'),
    'huesped' || gs || '@correo.com',
    '7000-' || LPAD(gs::TEXT, 4, '0'),
    DATE '2025-01-01' + (gs % 365)
FROM generate_series(1, 120) AS gs;

-- Empleados
INSERT INTO empleado (id_hotel, nombres, apellidos, cargo, email)
SELECT
    1 AS id_hotel,
    'Empleado' || gs,
    'Hotel' || gs,
    CASE
        WHEN gs % 4 = 0 THEN 'GERENCIA'
        WHEN gs % 4 = 1 THEN 'RECEPCION'
        WHEN gs % 4 = 2 THEN 'ADMINISTRACION'
        ELSE 'LIMPIEZA'
    END,
    'empleado' || gs || '@hotel.com'
FROM generate_series(1, 12) AS gs;

-- Servicios adicionales
INSERT INTO servicio (nombre, categoria, precio) VALUES
('Desayuno buffet', 'RESTAURANTE', 12.00),
('Cena ejecutiva', 'RESTAURANTE', 22.00), 
('Lavado normal', 'LAVANDERIA', 6.50),
('Lavado express', 'LAVANDERIA', 10.00),
('Masaje relajante', 'SPA', 45.00),
('Piedras spa', 'SPA', 60.00),
('Traslado aeropuerto', 'TRANSPORTE', 30.00),
('Tour local', 'TRANSPORTE', 55.00),
('Minibar', 'OTRO', 15.00),
('Decoracion especial', 'OTRO', 35.00);

-- Reservas
INSERT INTO reserva (
    codigo_reserva,
    id_huesped,
    id_habitacion,
    fecha_inicio,
    fecha_fin,
    num_huespedes,
    estado
)
SELECT
    'RES-' || LPAD(gs::TEXT, 6, '0'),
    ((gs - 1) % 120) + 1,
    ((gs - 1) % 60) + 1,
    DATE '2026-01-05' + (((gs - 1) / 60) * 20) + ((gs - 1) % 5),
    DATE '2026-01-05' + (((gs - 1) / 60) * 20) + ((gs - 1) % 5) + ((gs % 3) + 1),
    1,
    CASE
        WHEN gs <= 45 THEN 'FINALIZADA'
        WHEN gs <= 75 THEN 'CHECK_IN'
        WHEN gs <= 110 THEN 'CONFIRMADA'
        ELSE 'CANCELADA'
    END
FROM generate_series(1, 120) AS gs;

-- Estancias
INSERT INTO estancia (
    id_reserva,
    id_empleado_checkin,
    id_empleado_checkout,
    fecha_hora_checkin,
    fecha_hora_checkout,
    observaciones
)
SELECT
    r.id_reserva,
    ((r.id_reserva - 1) % 12) + 1,
    CASE WHEN r.estado = 'FINALIZADA' THEN ((r.id_reserva) % 12) + 1 ELSE NULL END,
    r.fecha_inicio + TIME '14:00',
    CASE WHEN r.estado = 'FINALIZADA' THEN r.fecha_fin + TIME '11:00' ELSE NULL END,
    CASE WHEN r.estado = 'FINALIZADA' THEN 'Estancia finalizada sin incidentes.' ELSE 'Estancia activa.' END
FROM reserva r
WHERE r.estado IN ('FINALIZADA', 'CHECK_IN');

-- Consumos de servicios
INSERT INTO consumo_servicio (id_estancia, id_servicio, fecha_consumo, cantidad, precio_unitario)
SELECT
    ((gs - 1) % (SELECT COUNT(*) FROM estancia)) + 1,
    ((gs - 1) % 10) + 1,
    TIMESTAMP '2026-01-06 10:00:00' + (gs || ' hours')::INTERVAL,
    (gs % 4) + 1,
    s.precio
FROM generate_series(1, 180) AS gs
JOIN servicio s ON s.id_servicio = ((gs - 1) % 10) + 1;

-- Facturas
INSERT INTO factura (
    id_estancia,
    numero_factura,
    subtotal_habitacion,
    subtotal_servicios,
    impuestos,
    total,
    estado
)
SELECT
    e.id_estancia,
    'FAC-' || LPAD(e.id_estancia::TEXT, 6, '0'),
    ((r.fecha_fin - r.fecha_inicio) * th.precio_noche)::NUMERIC(10,2) AS subtotal_habitacion,
    COALESCE(SUM(cs.total), 0)::NUMERIC(10,2) AS subtotal_servicios,
    ROUND((((r.fecha_fin - r.fecha_inicio) * th.precio_noche) + COALESCE(SUM(cs.total), 0)) * 0.13, 2) AS impuestos,
    ROUND((((r.fecha_fin - r.fecha_inicio) * th.precio_noche) + COALESCE(SUM(cs.total), 0)) * 1.13, 2) AS total,
    CASE WHEN e.id_estancia % 3 = 0 THEN 'PAGADA' ELSE 'EMITIDA' END
FROM estancia e
JOIN reserva r ON r.id_reserva = e.id_reserva
JOIN habitacion h ON h.id_habitacion = r.id_habitacion
JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
LEFT JOIN consumo_servicio cs ON cs.id_estancia = e.id_estancia
WHERE r.estado = 'FINALIZADA'
GROUP BY e.id_estancia, r.fecha_inicio, r.fecha_fin, th.precio_noche;
