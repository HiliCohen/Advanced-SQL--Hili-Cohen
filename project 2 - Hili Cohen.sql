use WideWorldImporters 
go

-----1
go

with CTE	
as 
(select YEAR(o.orderdate) as Year,
	COUNT(distinct month(o.OrderDate)) as NumberOfMonthsPerYear,
	sum(ord.PickedQuantity* ord.UnitPrice) as IncomePerYear,
	sum(ord.PickedQuantity* ord.UnitPrice)/COUNT(distinct month(o.OrderDate)) *12 as YearlyLinearIncome,
	LAG(sum(ord.PickedQuantity* ord.UnitPrice)/COUNT(distinct month(o.OrderDate))*12,1)over(order by year(o.orderdate)) as IncomePrevYear
	from Sales.Orders o join Sales.OrderLines ord
	on o.OrderID = ord.OrderID
	group by YEAR(o.OrderDate))

select cte.Year,
CTE.NumberOfMonthsPerYear,
CTE.IncomePerYear,
format ( cte.YearlyLinearIncome,'#.00') as YearlyLinearIncome,
format ((CTE.YearlyLinearIncome-CTE.IncomePrevYear)/CTE.incomeprevyear *100,'#0.00') as GrowthRate
from cte
order by CTE.Year


----2
go

with Quartelysum 
as
(select c.customerid,
		YEAR(o.OrderDate) as the_year,
		DATEPART(qq,o.OrderDate) as the_quarter,
		c.CustomerName,
		sum(ord.PickedQuantity*ord.UnitPrice) as Income
		from Sales.Orders o join Sales.Customers c
		on o.CustomerID = c.CustomerID
		join Sales.OrderLines ord
		on o.OrderID = ord.OrderID
		group by c.CustomerID, c.CustomerName,YEAR(o.OrderDate),DATEPART(qq,o.OrderDate)),
ranked
as 
	(select Quartelysum.CustomerName,
		Quartelysum.the_year,
		Quartelysum.the_quarter,
		Quartelysum.Income,
		DENSE_RANK()over(partition by Quartelysum.the_year,Quartelysum.the_quarter order by Quartelysum.income desc) as DNR
		from Quartelysum)

select ranked.the_year,
		ranked.the_quarter,
		ranked.CustomerName,
		ranked.Income,
		ranked.DNR
from ranked
where ranked.DNR <=5
order by ranked.the_year, ranked.the_quarter,ranked.DNR

----3
go

with ProFit
as 
(select sum(si.ExtendedPrice-si.TaxAmount) as totalprofit,
		st.StockItemID,
		st.StockItemName,
		RANK()over(order by sum(si.ExtendedPrice-si.TaxAmount)desc) as RN
from Sales.InvoiceLines si join Warehouse.StockItems st
on si.StockItemID = st.StockItemID
group by st.StockItemID,st.StockItemName)

select  p.StockItemID,
		p.StockItemName,
		p.totalprofit
from ProFit p
where p.RN <=10
order by p.RN


----4
go

with stockitemscheck 
as 
(select st.StockItemID,
		st.StockItemName,
		st.UnitPrice,
		st.RecommendedRetailPrice,
		(st.RecommendedRetailPrice-st.UnitPrice) as NominalProductProfit,
		dense_rank()over(order by (st.RecommendedRetailPrice-st.unitprice)desc) as DNR
from Warehouse.StockItems st
group by st.StockItemID,st.StockItemName,st.UnitPrice,st.RecommendedRetailPrice)

select  ROW_NUMBER()over(order by s.NominalProductProfit desc) as RN,
		s.StockItemID,
		s.StockItemName,
		s.UnitPrice,
		s.RecommendedRetailPrice,
		s.NominalProductProfit,
		s.DNR
from stockitemscheck s
order by ROW_NUMBER()over(order by s.NominalProductProfit desc)

-----5
go

with Productdetalis
as 
(select concat_ws(' - ',s.SupplierID,s.SupplierName) as SupplierDetalis, 
					STUFF((select ' /, '+ CAST(st.StockItemID as varchar)+' '+ st.StockItemName
					from Warehouse.StockItems st
					where s.SupplierID = st.SupplierID
					for XML path ('')),1,4,'') as ProductDetalis
from Purchasing.Suppliers s)

select pro.SupplierDetalis, pro.ProductDetalis
from Productdetalis pro
where pro.ProductDetalis is not null

-----6
go

with Totalextendedwithcutomer
as
(select c.CustomerID,
		sum(invl.ExtendedPrice) as TotalExtendedPrice
from Sales.Invoices inv join Sales.Customers c
on c.CustomerID = inv.CustomerID
join Sales.InvoiceLines invl
on inv.InvoiceID = invl.InvoiceID
group by c.CustomerID),

geograficdetails
as
(select ac.CityName,
		cu.CountryName,
		cu.Continent,
		cu.Region,
		c.CustomerID
from Application.StateProvinces s join Application.Cities ac
on ac.StateProvinceID = s.StateProvinceID
join Application.Countries cu
on s.CountryID = cu.CountryID 
join Sales.Customers c 
on ac.CityID = c.PostalCityID)

select top (5) t.CustomerID,
			 g.CityName,
			 g.CountryName,
			 g.Continent,
			 g.Region,
			FORMAT(t.TotalExtendedPrice,'#,0.00') as TotalExtendedPrice
from Totalextendedwithcutomer t join geograficdetails g
on t.CustomerID = g.CustomerID
order by t.TotalExtendedPrice desc 

---7
go

with Monthlytotals
as
(select YEAR(o.OrderDate) as orderYear,
		month(o.OrderDate) as ordermonth2,
		sum(ord.UnitPrice * ord.Quantity) as monthlytotal
		from Sales.Orders o join Sales.OrderLines ord
		on o.OrderID = ord.OrderID
		group by YEAR(o.OrderDate),MONTH(o.OrderDate)),

CumulativeTotal 
AS 
(select YEAR(o.OrderDate) AS OrderYear,
		SUM(ord.PickedQuantity*ord.UnitPrice) as yearlytotal
		from Sales.Orders o join Sales.OrderLines ord
		on o.OrderID = ord.OrderID
		group by YEAR(o.OrderDate)),

Unionmonth
as (select m.orderYear,
			CAST(m.ordermonth2 as varchar) ordermonth,
			m.monthlytotal,
			m.ordermonth2
		from Monthlytotals m
union
	select c.OrderYear,
		'Grand Total',
		c.yearlytotal,
		13
	from CumulativeTotal c)

select Um.orderYear,
		Um.ordermonth,
format(Um.monthlytotal,'#,#.00') as MonthlyTotal,
	case
		when ISNUMERIC (um.ordermonth)=1
		then format(sum(Um.monthlytotal)over (partition by um.orderyear order by ordermonth2),'#,#.00')
		else FORMAT(MAX(MonthlyTotal)OVER(PARTITION BY um.orderyear ORDER BY ordermonth2), '#,#.00')
		end CumulativeTotal

from Unionmonth Um
order by Um.orderYear,Um.ordermonth2

----8
SELECT ordermonth, [2013],[2014],[2015],[2016]
FROM(select OrderID ,YEAR(orderdate) as orderyear,MONTH(OrderDate) as ordermonth
from Sales.Orders)P
PIVOT(COUNT(ORDERID) FOR ORDERYEAR IN ([2013],[2014],[2015],[2016]))PVT
ORDER BY ordermonth

---9
go

with orderdates
as
(SELECT C.CustomerID,
		C.CustomerName,
		O.OrderDate,
		LAG(O.ORDERDATE,1)OVER(partition BY c.CUSTOMERID order by o.orderdate)as PreviousOrderDate,
		DATEDIFF(dd,(LAG(o.OrderDate,1)OVER(PARTITION BY c.CustomerID ORDER BY o.OrderDate)),o.OrderDate)as Daysincelastcustomerorder,
		DATEDIFF(dd,MAX(o.OrderDate)OVER(PARTITION BY c.CustomerID),MAX(o.OrderDate)OVER()) as DaysSinceLastOrder
FROM Sales.Orders o JOIN Sales.Customers c
ON o.customerid = C.CustomerID),

customerstatus 
as 
(Select o.CustomerID,
		o.CustomerName,
		o.OrderDate,
		SUM(Daysincelastcustomerorder)OVER(PARTITION BY CustomerID) / COUNT(Daysincelastcustomerorder)OVER(PARTITION BY CustomerID) as Avgdaysbetweenorders,
		o.PreviousOrderDate,
		o.DaysSinceLastOrder
	from orderdates o)

select  cs.CustomerID,
		cs.CustomerName,
		cs.OrderDate,
		cs.PreviousOrderDate,
		cs.DaysSinceLastOrder,
		cs.Avgdaysbetweenorders,
			case
				when cs.DaysSinceLastOrder>2*cs.Avgdaysbetweenorders
				then 'Potential Churn'
				else 'active'
				end Customerstatus 
from customerstatus cs 


---10
go

with Uniqcust
as
(
select  c.CustomerID,
		c.CustomerCategoryID,
		cc.CustomerCategoryName,
		case 
		when c.CustomerName LIKE '%Wingtip%' then 'Wingtip Customers'
		when c.CustomerName LIKE '%Tailspin%' then 'Tailspin Customers'
		else c.CustomerName
		end  CustomerName
from Sales.Customers c JOIN Sales.CustomerCategories cc
on cc.CustomerCategoryID = c.CustomerCategoryID),

Amountcust
as
(select u.CustomerCategoryName
		,COUNT(distinct u.CustomerName) CustomerCOUNT
from Uniqcust u
group by u.CustomerCategoryName)

select  a.CustomerCategoryName,
		a.CustomerCOUNT,
		sum(CustomerCOUNT)over() TotalCustCount,
		format(cast(a.CustomerCOUNT AS FLOAT)/sum(a.CustomerCOUNT)over(), '#.00%') DistributionFactor
FROM Amountcust a
ORDER BY CustomerCategoryName





