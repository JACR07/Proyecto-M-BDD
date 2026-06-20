-- Proyecto final, bases de datos
-- Este archivo sql contiene la demostración
-- de los objetos programados 

SET search_path TO hotel_reservas;

-- 1. Funcion: calcular noches de una reserva.
SELECT
    id_reserva,
    codigo_reserva,
    fn_noches_reserva(id_reserva) AS noches
FROM reserva
ORDER BY id_reserva
LIMIT 5;

-- 2. Trigger
-- Este INSERT debe fallar porque intenta reservar una habitacion
-- en un periodo ya ocupado por una reserva confirmada/check-in.

INSERT INTO reserva (
    codigo_reserva,
    id_huesped,
    id_habitacion,
    fecha_inicio,
    fecha_fin,
    num_huespedes,
    estado
)
VALUES (
    'RES-CONFLICTO',
    1,
    1,
    DATE '2026-01-05',
    DATE '2026-01-07',
    1,
    'CONFIRMADA'
);


-- 3. Procedimiento de check-out:
-- Crea factura para una estancia activa que aun no tenga factura.
-- Se toma una reserva en CHECK_IN.
DO $$
DECLARE
    v_reserva BIGINT;
BEGIN
    SELECT r.id_reserva
    INTO v_reserva
    FROM reserva r
    JOIN estancia e ON e.id_reserva = r.id_reserva
    WHERE r.estado = 'CHECK_IN'
      AND NOT EXISTS (
          SELECT 1
          FROM factura f
          WHERE f.id_estancia = e.id_estancia
      )
    ORDER BY r.id_reserva
    LIMIT 1;

    IF v_reserva IS NOT NULL THEN
        CALL sp_realizar_checkout(v_reserva, 1);
    END IF;
END $$;

-- Sirve para la verificacion de la factura generada por el procedimiento.
SELECT
    f.numero_factura,
    r.codigo_reserva,
    f.subtotal_habitacion,
    f.subtotal_servicios,
    f.impuestos,
    f.total,
    f.estado
FROM factura f
JOIN estancia e ON e.id_estancia = f.id_estancia
JOIN reserva r ON r.id_reserva = e.id_reserva
ORDER BY f.id_factura DESC
LIMIT 5;