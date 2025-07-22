CREATE TABLE sales.customer_log (
    log_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT,
    action VARCHAR(50),
    log_date DATETIME DEFAULT GETDATE()
);

CREATE TABLE production.price_history (
    history_id INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT,
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2),
    change_date DATETIME DEFAULT GETDATE(),
    changed_by NVARCHAR(100)
);

CREATE TABLE sales.order_audit (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id INT,
    customer_id INT,
    store_id INT,
    staff_id INT,
    order_date DATE,
    audit_timestamp DATETIME DEFAULT GETDATE()
);

CREATE NONCLUSTERED INDEX ix_cust_email
ON sales.customers(email);

CREATE NONCLUSTERED INDEX ix_prod_cat_brand
ON production.products(category_id, brand_id);

CREATE NONCLUSTERED INDEX ix_orders_date_include
ON sales.orders(order_date)
INCLUDE (customer_id, store_id, order_status);

CREATE TRIGGER trg_InsertCustomerActivity
ON sales.customers
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO sales.customer_log (customer_id, action, log_date)
    SELECT customer_id, 'New Customer Added', GETDATE()
    FROM inserted;
END;

CREATE TRIGGER trg_TrackPriceChange
ON production.products
AFTER UPDATE
AS
BEGIN
    IF UPDATE(list_price)
    BEGIN
        INSERT INTO production.price_history(product_id, old_price, new_price, changed_by)
        SELECT 
            i.product_id,
            d.list_price,
            i.list_price,
            SYSTEM_USER
        FROM inserted i
        JOIN deleted d ON i.product_id = d.product_id;
    END
END;

CREATE TRIGGER trg_PreventCategoryRemoval
ON production.categories
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM production.products p 
        JOIN deleted d ON p.category_id = d.category_id
    )
    BEGIN
        RAISERROR('Cannot remove category: linked products exist.', 16, 1);
    END
    ELSE
    BEGIN
        DELETE FROM production.categories
        WHERE category_id IN (SELECT category_id FROM deleted);
    END
END;

CREATE TRIGGER trg_AdjustStock
ON sales.order_items
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ps
    SET ps.quantity = ps.quantity - i.quantity
    FROM production.stocks ps
    JOIN inserted i 
        ON ps.product_id = i.product_id
    WHERE ps.store_id = (SELECT store_id FROM sales.orders WHERE order_id = i.order_id);
END;

CREATE TRIGGER trg_RecordOrderAudit
ON sales.orders
AFTER INSERT
AS
BEGIN
    INSERT INTO sales.order_audit(order_id, customer_id, store_id, staff_id, order_date)
    SELECT order_id, customer_id, store_id, staff_id, order_date
    FROM inserted;
END;