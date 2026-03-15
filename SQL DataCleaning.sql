Use FashionShop
Go

-- Đếm số bảng 
SELECT COUNT(*) AS Total_Tables
FROM sys.tables
WHERE name <> 'sysdiagrams';

SELECT name AS TableName
FROM sys.tables
WHERE name <> 'sysdiagrams';


;WITH rc AS (
  SELECT object_id, SUM(rows) AS [RowCount]
  FROM sys.partitions
  WHERE index_id IN (0,1)
  GROUP BY object_id
),
cc AS (
  SELECT object_id, COUNT(*) AS [ColumnCount]
  FROM sys.columns
  GROUP BY object_id
)
SELECT t.name AS TableName,
       ISNULL(rc.[RowCount],0)  AS [Rows],
       ISNULL(cc.[ColumnCount],0) AS [Columns]
FROM sys.tables t
LEFT JOIN rc ON rc.object_id = t.object_id
LEFT JOIN cc ON cc.object_id = t.object_id
WHERE SCHEMA_NAME(t.schema_id) = 'dbo'
  AND t.name <> 'sysdiagrams'
ORDER BY t.name;

--Birthday
-- Cấu hình phạm vi tuổi nghiên cứu
DECLARE @MinAge INT = 12, @MaxAge INT = 60;

-- Preview: các birthday “outlier”
SELECT Partner_ID, Birthday,
       DATEDIFF(YEAR, Birthday, GETDATE()) AS AgeYears
FROM dbo.Partner_Info
WHERE Birthday IS NOT NULL
  AND (
        Birthday > GETDATE() OR
        DATEDIFF(YEAR, Birthday, GETDATE()) < @MinAge OR
        DATEDIFF(YEAR, Birthday, GETDATE()) > @MaxAge
      )
ORDER BY Birthday;

-- UPDATE: null hóa các birthday outlier
UPDATE dbo.Partner_Info
SET Birthday = NULL
WHERE Birthday IS NOT NULL
  AND (
        Birthday > GETDATE() OR
        DATEDIFF(YEAR, Birthday, GETDATE()) < @MinAge OR
        DATEDIFF(YEAR, Birthday, GETDATE()) > @MaxAge
      );


ALTER TABLE Partner_Info
ADD Age INT NULL;

UPDATE Partner_Info
SET Age = DATEDIFF(YEAR, Birthday, GETDATE()) 
          - CASE 
                WHEN DATEADD(YEAR, DATEDIFF(YEAR, Birthday, GETDATE()), Birthday) > GETDATE() 
                THEN 1 
                ELSE 0 
            END
WHERE Birthday IS NOT NULL;

SELECT AVG(CAST(
    DATEDIFF(YEAR, Birthday, GETDATE()) 
    - CASE 
          WHEN DATEADD(YEAR, DATEDIFF(YEAR, Birthday, GETDATE()), Birthday) > GETDATE() 
          THEN 1 
          ELSE 0 
      END
AS FLOAT)) AS AvgAge
FROM Partner_Info
WHERE Birthday IS NOT NULL;

UPDATE Partner_Info
SET Age = (
    SELECT AVG(CAST(
        DATEDIFF(YEAR, Birthday, GETDATE()) 
        - CASE 
              WHEN DATEADD(YEAR, DATEDIFF(YEAR, Birthday, GETDATE()), Birthday) > GETDATE() 
              THEN 1 
              ELSE 0 
          END
    AS FLOAT))
    FROM Partner_Info
    WHERE Birthday IS NOT NULL
)
WHERE Age IS NULL;


--Gender
-- Preview: các giá trị Gender ngoài 0/1
SELECT Partner_ID, Gender FROM dbo.Partner_Info
WHERE Gender IS NOT NULL AND CAST(Gender AS INT) NOT IN (0,1);

-- UPDATE: chuẩn hoá
UPDATE dbo.Partner_Info
SET Gender = NULL
WHERE Gender IS NOT NULL AND CAST(Gender AS INT) NOT IN (0,1);

-- tính mode vào biến
DECLARE @ModeGender INT;

SELECT TOP 1
    @ModeGender = CAST(Gender AS INT)
FROM dbo.Partner_Info
WHERE Gender IS NOT NULL
GROUP BY CAST(Gender AS INT)
ORDER BY COUNT(*) DESC;

-- xem mode là gì
SELECT @ModeGender AS ModeGender;

-- điền thiếu bằng mode
UPDATE dbo.Partner_Info
SET Gender = @ModeGender
WHERE Gender IS NULL;

--Address
;WITH addr AS (
    SELECT
        o.Partner_ID,
        o.[Shipping_Ward_Commune]  AS Ward,
        o.[Shipping_Province_City] AS City,
        COUNT(*) AS Used,
        MAX(o.Create_Date) AS LatestUse
    FROM dbo.[Order] o
    WHERE o.[Partner_ID] IS NOT NULL
      AND o.[Shipping_Ward_Commune]  IS NOT NULL
      AND o.[Shipping_Province_City] IS NOT NULL
    GROUP BY o.Partner_ID, o.[Shipping_Ward_Commune], o.[Shipping_Province_City]
),
pick AS (
    SELECT *
    FROM (
        SELECT *,
               ROW_NUMBER() OVER(
                 PARTITION BY Partner_ID
                 ORDER BY Used DESC, LatestUse DESC
               ) AS rn
        FROM addr
    ) s
    WHERE rn = 1
)
UPDATE pi
SET [Ward/Commune]  = COALESCE(pi.[Ward/Commune],  s.Ward),
    [Province/City] = COALESCE(pi.[Province/City], s.City)
FROM dbo.Partner_Info pi
JOIN pick s ON s.Partner_ID = pi.Partner_ID
WHERE pi.[Ward/Commune] IS NULL OR pi.[Province/City] IS NULL;


-- NAME
SELECT 
    Partner_ID,
    Partner_Name AS OriginalName,
    dbo.fn_ProperCase(Partner_Name) AS ProperName
FROM Partner_Info
WHERE LTRIM(RTRIM(Partner_Name)) COLLATE Latin1_General_CS_AS
      <> dbo.fn_ProperCase(Partner_Name) COLLATE Latin1_General_CS_AS;

UPDATE Partner_Info
SET Partner_Name = dbo.fn_ProperCase(LTRIM(RTRIM(Partner_Name)))
WHERE LTRIM(RTRIM(Partner_Name)) COLLATE Latin1_General_CS_AS
      <> dbo.fn_ProperCase(Partner_Name) COLLATE Latin1_General_CS_AS;

Update pi
SET pi.Email = 'PHUONGBB@GMAIL.COM'
FROM Partner_Info pi
WHERE pi.Partner_ID = 'P0009';

SELECT Email
FROM Partner_Info
WHERE Partner_ID = 'P0009';

--Kiểm tra email không hợp lệ
SELECT 
    Partner_ID,
    Partner_Name,
    Email AS OriginalEmail,
    dbo.fn_NormalizeEmail(Email) AS NormalizedEmail
FROM dbo.Partner_Info
WHERE Email IS NOT NULL
  AND (
        dbo.fn_NormalizeEmail(Email) IS NULL
        OR LTRIM(RTRIM(Email)) COLLATE Latin1_General_CS_AS 
           <> dbo.fn_NormalizeEmail(Email) COLLATE Latin1_General_CS_AS
      );

UPDATE dbo.Partner_Info
SET Email = dbo.fn_NormalizeEmail(Email)
WHERE Email IS NOT NULL
  AND (
        dbo.fn_NormalizeEmail(Email) IS NULL
        OR LTRIM(RTRIM(Email)) COLLATE Latin1_General_CS_AS 
           <> dbo.fn_NormalizeEmail(Email) COLLATE Latin1_General_CS_AS
      );




--Thêm biến phân tích: Age & AgeGroup
--Tạo VIEW sạch để dùng cho phân tích:
CREATE OR ALTER VIEW dbo.vCustomer_Clean AS
SELECT
    pi.Partner_ID,
    pi.Partner_Name,
    p.Is_Supplier,
    CAST(CASE WHEN pi.Gender IS NULL THEN NULL ELSE CAST(pi.Gender AS INT) END AS TINYINT) AS Gender,
    pi.Email,
    pi.PhoneNumber,
    pi.[Ward/Commune],
    pi.[Province/City],
    pi.Age,
    CASE 
        WHEN pi.Age IS NULL THEN 'Unknown'
        WHEN pi.Age < 18 THEN '<18'
        WHEN pi.Age BETWEEN 18 AND 24 THEN '18-24'
        WHEN pi.Age BETWEEN 25 AND 34 THEN '25-34'
        WHEN pi.Age BETWEEN 35 AND 44 THEN '35-44'
        WHEN pi.Age BETWEEN 45 AND 54 THEN '45-54'
        WHEN pi.Age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65+'
    END AS AgeGroup,

    -- PHÂN LOẠI B2B / B2C
    CASE 
        -- Nếu bạn có cột Is_Company thì ưu tiên dùng:
        -- WHEN p.Is_Company = 1 THEN N'B2B'

        -- Hoặc heuristic theo tên pháp nhân:
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%Công ty%' THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%CTY%'      THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%TNHH%'     THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%Cổ phần%'  THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%Doanh nghiệp%' THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%Shop%'     THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%May mặc%'  THEN N'B2B'
        WHEN pi.Partner_Name COLLATE Vietnamese_CI_AI LIKE N'%Fashion%'  THEN N'B2B'
        -- Nếu là nhà cung cấp cũng xem như B2B mua sỉ
        WHEN p.Is_Supplier = 1 THEN N'B2B'
        ELSE N'B2C'
    END AS CustomerType
FROM dbo.Partner_Info pi
JOIN dbo.Partner p ON p.Partner_ID = pi.Partner_ID
WHERE p.Is_Customer = 1 AND p.Is_Supplier = 0;


-- Xóa space dư đầu/cuối, đổi space kép thành 1 space
UPDATE dbo.Partner_Info
SET Partner_Name = LTRIM(RTRIM(REPLACE(REPLACE(Partner_Name, CHAR(9), ' '), '  ', ' ')));


--Chuẩn hóa Name
CREATE OR ALTER FUNCTION dbo.fn_ProperCase (@Text NVARCHAR(4000))
RETURNS NVARCHAR(4000)
AS
BEGIN
    -- Danh sách các tiền tố doanh nghiệp
    DECLARE @KeepList TABLE (Prefix NVARCHAR(100));
    INSERT INTO @KeepList VALUES 
        (N'Công ty'), 
        (N'Doanh nghiệp'),
        (N'Tập đoàn'),
        (N'Chi nhánh'),
        (N'Trung tâm'),
        (N'Cửa hàng');

    -- Bỏ khoảng trắng thừa đầu/cuối
    SET @Text = LTRIM(RTRIM(@Text));

    -- Nếu tên bắt đầu bằng 1 trong các prefix thì trả nguyên gốc
    IF EXISTS (
        SELECT 1 
        FROM @KeepList 
        WHERE @Text LIKE Prefix + N'%'
    )
        RETURN @Text;

    ---------------------------------
    -- Ngược lại: proper-case bình thường
    ---------------------------------
    DECLARE @Result NVARCHAR(4000) = '';
    DECLARE @Word NVARCHAR(100);
    DECLARE @Pos INT;

    WHILE LEN(@Text) > 0
    BEGIN
        SET @Pos = CHARINDEX(' ', @Text + ' ');
        SET @Word = SUBSTRING(@Text, 1, @Pos - 1);

        -- Nếu từ viết tắt đặc biệt thì giữ nguyên
        IF UPPER(@Word) IN ('TNHH','CP','CTY','MTV','VN','TP')
            SET @Result = @Result + UPPER(@Word) + ' ';
        ELSE
            SET @Result = @Result 
                        + UPPER(LEFT(@Word,1)) 
                        + LOWER(SUBSTRING(@Word,2,LEN(@Word))) + ' ';

        SET @Text = LTRIM(SUBSTRING(@Text, @Pos+1, LEN(@Text)));
    END

    RETURN RTRIM(@Result);
END;
GO


--Chuẩn hóa Email
CREATE OR ALTER FUNCTION dbo.fn_NormalizeEmail (@Email NVARCHAR(320))
RETURNS NVARCHAR(320)
AS
BEGIN
    DECLARE @Result NVARCHAR(320);
    DECLARE @AtPos INT;
    DECLARE @Domain NVARCHAR(320);

    -- Bỏ NULL hoặc chuỗi rỗng
    IF @Email IS NULL OR LTRIM(RTRIM(@Email)) = ''
        RETURN NULL;

    -- 1. Xóa khoảng trắng dư đầu/cuối
    SET @Result = LTRIM(RTRIM(@Email));

    -- 2. Bỏ hết khoảng trắng giữa chuỗi
    SET @Result = REPLACE(@Result, ' ', '');

    -- 3. Đưa về chữ thường toàn bộ
    SET @Result = LOWER(@Result);

    -- 4. Kiểm tra có đúng 1 dấu @
    IF (LEN(@Result) - LEN(REPLACE(@Result, '@', ''))) <> 1
        RETURN NULL;

    -- 5. Lấy domain sau @
    SET @AtPos = CHARINDEX('@', @Result);
    SET @Domain = SUBSTRING(@Result, @AtPos + 1, LEN(@Result));

    -- 6. Domain phải có dạng "tên + dấu chấm + hậu tố"
    -- Ví dụ: gmail.com, icloud.com, yahoo.vn
    IF CHARINDEX('.', @Domain) = 0 
        RETURN NULL;

    -- Domain trước dấu chấm phải có ít nhất 1 ký tự
    IF LEFT(@Domain, CHARINDEX('.', @Domain) - 1) = ''
        RETURN NULL;

    -- Domain sau dấu chấm cũng phải có ít nhất 2 ký tự (com, vn, org,...)
    IF LEN(SUBSTRING(@Domain, CHARINDEX('.', @Domain) + 1, LEN(@Domain))) < 2
        RETURN NULL;

    RETURN @Result;
END;
GO



-- Clean Shipping_Ward_Commune
UPDATE dbo.[Order]
SET [Shipping_Ward_Commune] = dbo.fn_ProperCase(LTRIM(RTRIM([Shipping_Ward_Commune])))
WHERE [Shipping_Ward_Commune] IS NOT NULL;

-- Clean Shipping_Province_City
UPDATE dbo.[Order]
SET [Shipping_Province_City] = dbo.fn_ProperCase(LTRIM(RTRIM([Shipping_Province_City])))
WHERE [Shipping_Province_City] IS NOT NULL;


;WITH Base AS (
  SELECT 
    o.Order_ID,
    Ward     = LTRIM(RTRIM(o.[Shipping_Ward_Commune])),
    BaseName = LTRIM(RTRIM(
                 REPLACE(REPLACE(REPLACE(LOWER(o.[Shipping_Ward_Commune]),
                   N'phường ', ''), N'xã ', ''), N'thị trấn ', '')
               ))
  FROM [Order] o
),
Pick AS (  -- chọn 1 bản ghi có prefix chuẩn để gom
  SELECT BaseName, MIN(Ward) AS WardDisplay
  FROM Base
  WHERE Ward LIKE N'Phường %' OR Ward LIKE N'Xã %' OR Ward LIKE N'Thị trấn %'
  GROUP BY BaseName
)
SELECT 
  o.Order_ID,
  CurrentWard = o.[Shipping_Ward_Commune],
  NewWard     = ISNULL(pk.WardDisplay, o.[Shipping_Ward_Commune])
FROM [Order] o
JOIN Base b   ON b.Order_ID = o.Order_ID
LEFT JOIN Pick pk ON pk.BaseName = b.BaseName;

CREATE OR ALTER VIEW dbo.vCustomer_Spending AS
SELECT 
    o.Partner_ID,
    SUM(o.Total) AS TotalSpent,
    CASE 
        WHEN SUM(o.Total) < 500000 THEN N'<500k'
        WHEN SUM(o.Total) BETWEEN 500000 AND 1000000 THEN N'500k - 1tr'
        WHEN SUM(o.Total) BETWEEN 1000000 AND 5000000 THEN N'1tr - 5tr'
        ELSE N'>5tr'
    END AS SpendingGroup
FROM dbo.[Order] o
GROUP BY o.Partner_ID;

CREATE OR ALTER VIEW dbo.vCustomer_OrderFrequency AS
SELECT 
    o.Partner_ID,
    COUNT(o.Order_ID) AS OrderFrequency
FROM dbo.[Order] o
GROUP BY o.Partner_ID;

Update [Order]
Set Shipping_Province_City = N'Tỉnh An Giang'
Where Order_ID = 'ORD00059'

CREATE OR ALTER VIEW dbo.vOrder_Region AS
SELECT 
    o.Order_ID,
    CASE 
        WHEN o.[Shipping_Province_City] IN 
            (N'Thành Phố Hà Nội', N'Thành Phố Hải Phòng', N'Tỉnh Tuyên Quang', N'Tỉnh Lào Cai', N'Tỉnh Lai Châu',
             N'Tỉnh Điện Biên', N'Tỉnh Sơn La', N'Tỉnh Lạng Sơn', N'Tỉnh Cao Bằng', N'Tỉnh Phú Thọ',
             N'Tỉnh Quảng Ninh', N'Tỉnh Bắc Ninh', N'Tỉnh Hưng Yên', N'Tỉnh Ninh Bình', N'Tỉnh Thái Nguyên')
            THEN N'Miền Bắc'
        WHEN o.[Shipping_Province_City] IN
            (N'Thành Phố Đà Nẵng', N'Tỉnh Thừa Thiên Huế', N'Tỉnh Gia Lai', N'Tỉnh Quảng Ngãi', N'Tỉnh Quảng Trị',
             N'Tỉnh Nghệ An', N'Tỉnh Khánh Hòa', N'Tỉnh Bình Định', N'Tỉnh Thanh Hóa', N'Tỉnh Hà Tĩnh',
             N'Tỉnh Đắk Lắk', N'Tỉnh Lâm Đồng')
            THEN N'Miền Trung'
        WHEN o.[Shipping_Province_City] IN
            (N'Thành Phố Hồ Chí Minh', N'Thành Phố Cần Thơ', N'Tỉnh Đồng Nai', N'Tỉnh Tây Ninh', N'Tỉnh Vĩnh Long',
             N'Tỉnh Đồng Tháp', N'Tỉnh Cà Mau', N'Tỉnh An Giang')
            THEN N'Miền Nam'
        ELSE N'Khác'
    END AS Region
FROM dbo.[Order] o;

CREATE OR ALTER VIEW dbo.vCustomer_Monetary AS
SELECT 
    o.Partner_ID,
    SUM(o.Total) AS Monetary
FROM dbo.[Order] o
GROUP BY o.Partner_ID;

CREATE OR ALTER VIEW dbo.vCustomer_Recency AS
SELECT 
    o.Partner_ID,
    MAX(o.Create_Date) AS LastPurchaseDate,
    DATEDIFF(DAY, MAX(o.Create_Date), GETDATE()) AS RecencyDays
FROM dbo.[Order] o
GROUP BY o.Partner_ID;

CREATE OR ALTER VIEW dbo.vTopProducts AS
SELECT 
    od.Product_ID,
    p.Product_Name,
    o.Partner_ID,
    o.[Shipping_Province_City],
    SUM(od.Quantity) AS TotalQuantity,
    SUM(od.Total) AS TotalRevenue
FROM dbo.Order_Detail od
JOIN dbo.[Order] o ON o.Order_ID = od.Order_ID
JOIN dbo.Product p ON p.Product_ID = od.Product_ID
GROUP BY od.Product_ID, p.Product_Name, o.Partner_ID, o.[Shipping_Province_City];


SELECT 
    DATEDIFF(YEAR, Birthday, GETDATE()) 
    - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, Birthday, GETDATE()), Birthday) > GETDATE() THEN 1 ELSE 0 END 
    AS Age
FROM Partner_Info;

SELECT AVG(
    DATEDIFF(YEAR, Birthday, GETDATE()) 
    - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, Birthday, GETDATE()), Birthday) > GETDATE() THEN 1 ELSE 0 END
) AS AvgAge
FROM Partner_Info
WHERE Birthday IS NOT NULL;

