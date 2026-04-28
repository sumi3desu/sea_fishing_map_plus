RENAME TABLE teibou TO spots;

ALTER TABLE spots
  CHANGE COLUMN port_id spot_id INT NOT NULL,
  CHANGE COLUMN port_name spot_name VARCHAR(255) NOT NULL;
