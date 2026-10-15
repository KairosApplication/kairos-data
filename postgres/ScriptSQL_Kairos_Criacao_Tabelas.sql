-- ============================================================
-- DATABASE CREATION
-- ============================================================

CREATE TABLE Companies
(
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    cnpj VARCHAR(18) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    plan VARCHAR(20) NOT NULL
);

CREATE TABLE Users
(
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    birth_date DATE NOT NULL,
    cpf VARCHAR(14) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL
);

CREATE TABLE Sectors
(
    id SERIAL PRIMARY KEY,
    company_id INT NOT NULL REFERENCES Companies (id),
    name VARCHAR(100) NOT NULL,
    type VARCHAR NOT NULL,
    UNIQUE (company_id, name)
);

CREATE TABLE Aisles
(
    id SERIAL PRIMARY KEY,
    sector_id INT NOT NULL REFERENCES Sectors (id),
    position INT NOT NULL CHECK (position > 0),
    UNIQUE (sector_id, position)
);

CREATE TABLE Shelves
(
    id SERIAL PRIMARY KEY,
    aisle_id INT NOT NULL REFERENCES Aisles (id),
    maximum_capacity INT NOT NULL CHECK (maximum_capacity > 0)
);

CREATE TABLE Employees
(
    id SERIAL PRIMARY KEY,
    users_id INT UNIQUE NOT NULL REFERENCES Users (id),
    company_id INT NOT NULL REFERENCES Companies (id),
    position VARCHAR(100) NOT NULL CHECK (
        position IN ('MANAGER', 'STOCKER', 'CASHIER')
    )
);

CREATE TABLE Inventories
(
    id SERIAL PRIMARY KEY,
    company_id INT NOT NULL REFERENCES Companies (id),
    sector_id INT REFERENCES Sectors (id)
);

CREATE TABLE Inventory_Employees
(
    id SERIAL PRIMARY KEY,
    inventory_id INT NOT NULL REFERENCES Inventories (id),
    employee_id INT NOT NULL REFERENCES Employees (id),
    UNIQUE (inventory_id, employee_id)
);

CREATE TABLE Shelf_Employees
(
    id SERIAL PRIMARY KEY,
    shelf_id INT REFERENCES Shelves (id),
    employee_id INT REFERENCES Employees (id),
    UNIQUE (shelf_id, employee_id)
);

CREATE TABLE Employee_Aisles
(
    id SERIAL PRIMARY KEY,
    aisle_id INT REFERENCES Aisles (id),
    employee_id INT REFERENCES Employees (id),
    UNIQUE (employee_id, aisle_id)
);

CREATE TABLE Categories
(
    id SERIAL PRIMARY KEY,
    company_id INT NOT NULL REFERENCES Companies (id),
    category VARCHAR(50) NOT NULL,
    UNIQUE (company_id, category)
);

CREATE TABLE Products
(
    id SERIAL PRIMARY KEY,
    company_id INT NOT NULL REFERENCES Companies (id),
    brand VARCHAR,
    price MONEY CHECK (price >= 0::money),
    name VARCHAR(100) NOT NULL,
    category_id INT REFERENCES Categories (id)
);

CREATE TABLE Product_Shelves
(
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES Products (id),
    shelf_id INT NOT NULL REFERENCES Shelves (id),
    product_quantity INT NOT NULL CHECK (product_quantity > 0),
    UNIQUE (product_id, shelf_id)
);

CREATE TABLE Product_Inventories
(
    id SERIAL PRIMARY KEY,
    inventory_id INT NOT NULL REFERENCES Inventories (id),
    product_id INT NOT NULL REFERENCES Products (id),
    product_quantity INT NOT NULL CHECK (product_quantity >= 0),
    UNIQUE (inventory_id, product_id)
);

CREATE TABLE Restockings
(
    id SERIAL PRIMARY KEY,
    inventory_id INT NOT NULL REFERENCES Inventories (id),
    employee_id INT NOT NULL REFERENCES Employees (id),
    shelf_id INT NOT NULL REFERENCES Shelves (id),
    restocking_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    restocked_quantity INT NOT NULL CHECK (restocked_quantity > 0),
    qnt_avarias INT NOT NULL DEFAULT 0 CHECK (qnt_avarias >= 0),
    product_id INT NOT NULL REFERENCES Products (id)
);

CREATE TABLE Alerts
(
    id SERIAL PRIMARY KEY,
    stockout_date DATE,
    employee_id INT REFERENCES Employees (id),
    shelf_id INT NOT NULL REFERENCES Shelves (id),
    product_id INT REFERENCES Products (id),
    description VARCHAR(250) NOT NULL,
    status VARCHAR NOT NULL CHECK (
        status IN ('OPEN', 'RESOLVED', 'CANCELLED')
    ),
    resolution_date TIMESTAMP
);

CREATE TABLE Customers
(
    id SERIAL PRIMARY KEY,
    users_id INT UNIQUE NOT NULL REFERENCES Users (id),
    company_id INT NOT NULL REFERENCES Companies (id)
);

CREATE TABLE Purchases
(
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES Customers (id),
    date TIMESTAMP,
    status VARCHAR(20) NOT NULL CHECK (
        status IN ('IN_PROGRESS', 'COMPLETED', 'CANCELLED')
    )
);

CREATE TABLE Purchase_Products
(
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES Products (id),
    purchase_id INT NOT NULL REFERENCES Purchases (id),
    quantity INT NOT NULL CHECK (quantity > 0),
    amount MONEY NOT NULL CHECK (amount >= 0::money),
    UNIQUE (purchase_id, product_id)
);

CREATE TABLE Audits
(
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    operation VARCHAR(10) NOT NULL CHECK (
        operation IN ('INSERT', 'UPDATE', 'DELETE')
    ),
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_data JSONB,
    new_data JSONB,
    record_id INT,
    users VARCHAR(100)
);