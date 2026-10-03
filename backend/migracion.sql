-- Ejecutar UNA vez en MySQL antes de usar la app móvil.
-- Los hashes de contraseña miden ~160 caracteres; si la columna es más corta
-- (por ejemplo VARCHAR(50)), MySQL rechaza guardarlos.
USE floricola_db;
ALTER TABLE usuarios MODIFY password VARCHAR(255) NOT NULL;
