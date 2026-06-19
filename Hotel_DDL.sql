-- Proyecto Final BD - Escenario B: Sistema de Reservas de Hotel

DROP SCHEMA IF EXISTS hotel_reservas CASCADE;
CREATE SCHEMA hotel_reservas;
SET search_path TO hotel_reservas;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Tablas principales

CREATE TABLE hotel (
    id_hotel BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    direccion VARCHAR(200) NOT NULL,
    ciudad VARCHAR(80) NOT NULL,
    telefono VARCHAR(25) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    estrellas SMALLINT NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE tipo_habitacion (
    id_tipo_habitacion BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL UNIQUE,
    descripcion TEXT NOT NULL,
    capacidad SMALLINT NOT NULL CHECK (capacidad > 0),
    precio_noche NUMERIC(10,2) NOT NULL CHECK (precio_noche > 0)
);

CREATE TABLE habitacion (
    id_habitacion BIGSERIAL PRIMARY KEY,
    id_hotel BIGINT NOT NULL REFERENCES hotel(id_hotel) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_tipo_habitacion BIGINT NOT NULL REFERENCES tipo_habitacion(id_tipo_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT,
    numero VARCHAR(10) NOT NULL,
    piso SMALLINT NOT NULL CHECK (piso > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'DISPONIBLE'
        CHECK (estado IN ('DISPONIBLE', 'MANTENIMIENTO', 'OCUPADA')),
    CONSTRAINT uq_habitacion_hotel_numero UNIQUE (id_hotel, numero)
);

CREATE TABLE huesped (
    id_huesped BIGSERIAL PRIMARY KEY,
    nombres VARCHAR(80) NOT NULL,
    apellidos VARCHAR(80) NOT NULL,
    documento VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(120) NOT NULL UNIQUE,
    telefono VARCHAR(25) NOT NULL,
    fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE empleado (
    id_empleado BIGSERIAL PRIMARY KEY,
    id_hotel BIGINT NOT NULL REFERENCES hotel(id_hotel) ON UPDATE CASCADE ON DELETE RESTRICT,
    nombres VARCHAR(80) NOT NULL,
    apellidos VARCHAR(80) NOT NULL,
    cargo VARCHAR(40) NOT NULL
        CHECK (cargo IN ('RECEPCION', 'ADMINISTRACION', 'LIMPIEZA', 'GERENCIA')),
    email VARCHAR(120) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE reserva (
    id_reserva BIGSERIAL PRIMARY KEY,
    codigo_reserva VARCHAR(20) NOT NULL UNIQUE,
    id_huesped BIGINT NOT NULL REFERENCES huesped(id_huesped) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_habitacion BIGINT NOT NULL REFERENCES habitacion(id_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    num_huespedes SMALLINT NOT NULL CHECK (num_huespedes > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'CONFIRMADA'
        CHECK (estado IN ('CONFIRMADA', 'CHECK_IN', 'FINALIZADA', 'CANCELADA')),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_reserva_fechas CHECK (fecha_fin > fecha_inicio)
);

CREATE TABLE estancia (
    id_estancia BIGSERIAL PRIMARY KEY,
    id_reserva BIGINT NOT NULL UNIQUE REFERENCES reserva(id_reserva) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_empleado_checkin BIGINT NOT NULL REFERENCES empleado(id_empleado) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_empleado_checkout BIGINT REFERENCES empleado(id_empleado) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_hora_checkin TIMESTAMP NOT NULL,
    fecha_hora_checkout TIMESTAMP,
    observaciones TEXT,
    CONSTRAINT ck_estancia_checkout CHECK (
        fecha_hora_checkout IS NULL OR fecha_hora_checkout > fecha_hora_checkin
    )
);

CREATE TABLE servicio (
    id_servicio BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    categoria VARCHAR(40) NOT NULL
        CHECK (categoria IN ('RESTAURANTE', 'LAVANDERIA', 'SPA', 'TRANSPORTE', 'OTRO')),
    precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE consumo_servicio (
    id_consumo BIGSERIAL PRIMARY KEY,
    id_estancia BIGINT NOT NULL REFERENCES estancia(id_estancia) ON UPDATE CASCADE ON DELETE CASCADE,
    id_servicio BIGINT NOT NULL REFERENCES servicio(id_servicio) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_consumo TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad SMALLINT NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    total NUMERIC(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED
);

CREATE TABLE factura (
    id_factura BIGSERIAL PRIMARY KEY,
    id_estancia BIGINT NOT NULL UNIQUE REFERENCES estancia(id_estancia) ON UPDATE CASCADE ON DELETE RESTRICT,
    numero_factura VARCHAR(25) NOT NULL UNIQUE,
    fecha_emision TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    subtotal_habitacion NUMERIC(10,2) NOT NULL CHECK (subtotal_habitacion >= 0),
    subtotal_servicios NUMERIC(10,2) NOT NULL CHECK (subtotal_servicios >= 0),
    impuestos NUMERIC(10,2) NOT NULL CHECK (impuestos >= 0),
    total NUMERIC(10,2) NOT NULL CHECK (total >= 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'EMITIDA'
        CHECK (estado IN ('EMITIDA', 'PAGADA', 'ANULADA'))
);

-- Constraint para evitar doble reserva
ALTER TABLE reserva
ADD CONSTRAINT ex_reserva_sin_traslape
EXCLUDE USING gist (
    id_habitacion WITH =,
    daterange(fecha_inicio, fecha_fin, '[)') WITH &&
)
WHERE (estado IN ('CONFIRMADA', 'CHECK_IN'));

-- Funciones, Trigger Y Procedimiento

CREATE OR REPLACE FUNCTION fn_noches_reserva(p_id_reserva BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_noches INTEGER;
BEGIN
    SELECT (fecha_fin - fecha_inicio)
    INTO v_noches
    FROM reserva
    WHERE id_reserva = p_id_reserva;

    RETURN COALESCE(v_noches, 0);
END;
$$;

CREATE OR REPLACE FUNCTION fn_validar_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacidad SMALLINT;
BEGIN
    SELECT th.capacidad
    INTO v_capacidad
    FROM habitacion h
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
    WHERE h.id_habitacion = NEW.id_habitacion;

    IF NEW.num_huespedes > v_capacidad THEN
        RAISE EXCEPTION 'La habitacion solo permite % huesped(es), pero la reserva incluye %.',
            v_capacidad, NEW.num_huespedes;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM reserva r
        WHERE r.id_habitacion = NEW.id_habitacion
          AND r.id_reserva <> COALESCE(NEW.id_reserva, -1)
          AND r.estado IN ('CONFIRMADA', 'CHECK_IN')
          AND daterange(r.fecha_inicio, r.fecha_fin, '[)')
              && daterange(NEW.fecha_inicio, NEW.fecha_fin, '[)')
    ) THEN
        RAISE EXCEPTION 'La habitacion ya esta reservada en ese rango de fechas.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_reserva
BEFORE INSERT OR UPDATE OF id_habitacion, fecha_inicio, fecha_fin, num_huespedes, estado
ON reserva
FOR EACH ROW
WHEN (NEW.estado IN ('CONFIRMADA', 'CHECK_IN'))
EXECUTE FUNCTION fn_validar_reserva();

CREATE OR REPLACE PROCEDURE sp_realizar_checkout(
    p_id_reserva BIGINT,
    p_id_empleado_checkout BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_estancia BIGINT;
    v_noches INTEGER;
    v_precio_noche NUMERIC(10,2);
    v_subtotal_habitacion NUMERIC(10,2);
    v_subtotal_servicios NUMERIC(10,2);
    v_impuestos NUMERIC(10,2);
    v_total NUMERIC(10,2);
BEGIN
    SELECT e.id_estancia, fn_noches_reserva(r.id_reserva), th.precio_noche
    INTO v_id_estancia, v_noches, v_precio_noche
    FROM estancia e
    JOIN reserva r ON r.id_reserva = e.id_reserva
    JOIN habitacion h ON h.id_habitacion = r.id_habitacion
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
    WHERE r.id_reserva = p_id_reserva;

    IF v_id_estancia IS NULL THEN
        RAISE EXCEPTION 'No existe una estancia para la reserva %.', p_id_reserva;
    END IF;

    v_subtotal_habitacion := v_noches * v_precio_noche;

    SELECT COALESCE(SUM(total), 0)
    INTO v_subtotal_servicios
    FROM consumo_servicio
    WHERE id_estancia = v_id_estancia;

    v_impuestos := ROUND((v_subtotal_habitacion + v_subtotal_servicios) * 0.13, 2);
    v_total := v_subtotal_habitacion + v_subtotal_servicios + v_impuestos;

    UPDATE estancia
    SET fecha_hora_checkout = CURRENT_TIMESTAMP,
        id_empleado_checkout = p_id_empleado_checkout
    WHERE id_estancia = v_id_estancia
      AND fecha_hora_checkout IS NULL;

    UPDATE reserva
    SET estado = 'FINALIZADA'
    WHERE id_reserva = p_id_reserva;

    INSERT INTO factura (
        id_estancia,
        numero_factura,
        subtotal_habitacion,
        subtotal_servicios,
        impuestos,
        total,
        estado
    )
    VALUES (
        v_id_estancia,
        'FAC-' || LPAD(v_id_estancia::TEXT, 6, '0'),
        v_subtotal_habitacion,
        v_subtotal_servicios,
        v_impuestos,
        v_total,
        'EMITIDA'
    )
    ON CONFLICT (id_estancia) DO NOTHING;
END;
$$;