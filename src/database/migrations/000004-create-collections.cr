require "../../framework/database"

extend Ktistec::Database::Migration

up do |db|
  db.exec <<-STR
    CREATE TABLE collections (
      id integer PRIMARY KEY AUTOINCREMENT,
      created_at datetime NOT NULL,
      updated_at datetime NOT NULL,
      iri varchar(255) NOT NULL COLLATE NOCASE,
      items_iris text,
      total_items integer,
      first varchar(255),
      last varchar(255),
      prev varchar(255),
      next varchar(255),
      current varchar(255)
    )
  STR
  db.exec <<-STR
    CREATE UNIQUE INDEX idx_collections_iri
      ON collections (iri ASC)
  STR
end

down do |db|
  db.exec <<-STR
    DROP TABLE collections
  STR
end
