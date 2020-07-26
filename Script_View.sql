USE [CosmoSample]
GO

/****** Object:  View [dbo].[VW_SYS_NovinDoctorList]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_SYS_NovinDoctorList] AS
SELECT TOP 100000
	fCode as fCodeDoctor,fFirstName,fLastName,fCodeNezamPezeshki,
	CONCAT(fLastName ,' ',fFirstName) as DoctorName,
	Replace(CONCAT(fLastName,'-',fFirstName,fCodeNezamPezeshki),' ','') Total,
	Replace(CONCAT(fLastName,fFirstName,fCodeNezamPezeshki),' ','') Total2
FROM NovinDoctor
ORDER BY fLastName, fFirstName
 
GO

/****** Object:  View [dbo].[VW_SYS_TebnegarDoctorList]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_SYS_TebnegarDoctorList] AS
	WITH CTE AS
	(
		SELECT
			siDoctors,
			FileID,
			dbo.FN_FixLetter100(FName) as FName, 
			dbo.FN_FixLetter100(LName) as LName,
			MedicalID
		FROM dbo.DoctorsTable
	)
	SELECT TOP 100000
		siDoctors,
		FileID,
		FName,
		LName,
		Convert(int,MedicalID ) as MedicalID,
		CONCAT(LName,' ',FName) as DoctorName,
		Replace(CONCAT(LName,'-',FName,MedicalID),' ','') Total,
		Replace(CONCAT(LName,FName,MedicalID),' ','') Total2
	FROM CTE
	ORDER BY LName, FName
	
GO

/****** Object:  View [dbo].[VW_SYS_DoctorMatchList]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_SYS_DoctorMatchList] AS
	SELECT 
		fCodeDoctor, siDoctors, FileID, FName, LName, MedicalID, B.DoctorName 
	FROM VW_SYS_NovinDoctorList A
	INNER  JOIN  VW_SYS_TebnegarDoctorList B ON dbo.FN_FixLetter100(A.Total) = B.Total AND B.MedicalID IS NOT NULL 

GO

/****** Object:  View [tools].[VW_AllRelations]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 
 
CREATE   VIEW [tools].[VW_AllRelations] AS    
WITH CTE AS
(
	SELECT      
		K2.Name as FkName,  
		CONCAT(SCHEMA_NAME(SOH.schema_id),'.',OBJECT_NAME(FK.referenced_object_id),'.',SCH.Name) FullMaster,    
		CONCAT(SCHEMA_NAME(SOH.schema_id),'.',OBJECT_NAME(FK.referenced_object_id)) MasterTable,    
		SCHEMA_NAME(SOH.schema_id) MasterSchema,    
		OBJECT_NAME(FK.referenced_object_id) as [Master],     
		SCH.Name MasterKey,    
       
		CONCAT(SCHEMA_NAME(SOD.schema_id),'.',OBJECT_NAME(FK.parent_object_id),'.',SCD.Name) FullDetail,    
		CONCAT(SCHEMA_NAME(SOD.schema_id),'.',OBJECT_NAME(FK.parent_object_id)) DetailTable,    
		SCHEMA_NAME(SOD.schema_id) DetailSchema,    
		OBJECT_NAME(FK.parent_object_id) as Detail ,    
		SCD.Name ForeignKey,
		CASE K2.update_referential_action 
			WHEN  0 THEN 'NO ACTION'
			WHEN  1 THEN 'CASCADE'
			WHEN  2 THEN 'SET NULL'
			WHEN  3 THEN 'SET DEFAULT'
		END as update_referential_action, 
		CASE K2.delete_referential_action    
			WHEN  0 THEN 'NO ACTION'
			WHEN  1 THEN 'CASCADE'
			WHEN  2 THEN 'SET NULL'
			WHEN  3 THEN 'SET DEFAULT'
		END as delete_referential_action
    
	FROM SYS.foreign_key_columns FK    
	INNER JOIN sys.foreign_keys K2 ON FK.referenced_object_id = K2.referenced_object_id AND FK.parent_object_id = K2.parent_object_id and K2.Object_id = FK.constraint_object_id
	INNER JOIN SYS.columns SCH ON SCH.object_id = FK.referenced_object_id and SCH.column_id  = FK.referenced_column_id     
	INNER JOIN SYS.columns SCD ON SCD.object_id = FK.parent_object_id and SCD.column_id  = FK.parent_column_id     
	INNER JOIN SYS.objects SOH ON SCH.object_id = SOH.object_id    
	INNER JOIN SYS.objects SOD ON SCD.object_id = SOD.object_id    
)
SELECT
	FkName,FullMaster,MasterTable,MasterSchema,Master,MasterKey,FullDetail,DetailTable,DetailSchema,Detail,ForeignKey
	,CASE WHEN MasterTable= DetailTable THEN 1 ELSE 0 END IsSelfRelation,
	update_referential_action,delete_referential_action
FROM CTE 
 
GO

/****** Object:  View [tools].[VW_RemoveAndCreateRelations]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 
 
CREATE   VIEW [tools].[VW_RemoveAndCreateRelations] AS
	SELECT 
		'DropScript'='ALTER TABLE ['+DetailSchema+'].['+Detail+'] DROP CONSTRAINT  ['+FKName+']',
		'CreateScript'=
			'ALTER TABLE ['+DetailSchema+'].['+Detail+'] WITH CHECK ADD  CONSTRAINT ['+FKName+'] FOREIGN KEY(['+ForeignKey+']) '+
			'REFERENCES ['+MasterSchema+'].['+Master+'](['+MasterKey+']) '+
			'ON UPDATE '+ update_referential_action+' ON DELETE '+ delete_referential_action,
		FkName, MasterTable, Master, MasterKey, DetailTable, Detail, ForeignKey
	FROM tools.VW_AllRelations
 
 
 
GO

/****** Object:  View [dbo].[VW_Select_ListOfSergery]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_ListOfSergery] AS
	SELECT   
		FT.siFiles , FT.siDoctor, LTRIM(RTRIM(ST.SurgeryName)) as SurgeryName
	FROM  FilesTable FT 
	INNER JOIN AlbumTable AL ON FT.siFiles = AL.siFiles
	INNER JOIN AlbumSurgTable ALS ON ALS.siAlbum = AL.siAlbum
	INNER JOIN SurgeryTable ST ON ST.siSurgery = ALS.siSurgery
GO

/****** Object:  View [dbo].[VW_Select_ListOfSergeryFilterForDoctors]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_ListOfSergeryFilterForDoctors] AS
	SELECT  
		siDoctors,
		LTRIM(RTRIM( CAST(Item as varchar(50)) )) as Item
	FROM DoctorsTable D 
	CROSS APPLY dbo.FN_StringToTable_Not_NULL(Filter,',') 
GO

/****** Object:  View [dbo].[VW_Select_ListOfFilesWithForbidenSurgery]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_ListOfFilesWithForbidenSurgery] AS
	SELECT siFiles,siDoctor,SurgeryName
	FROM  VW_Select_ListOfSergery S
	INNER JOIN VW_Select_ListOfSergeryFilterForDoctors D ON S.siDoctor = D.siDoctors 
	WHERE SurgeryName =Item
GO

/****** Object:  View [dbo].[VW_BranchTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_BranchTable] AS
	Select siBranch, BranchName from BranchTable
GO

/****** Object:  View [dbo].[VW_CommonTariffTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
Create View [dbo].[VW_CommonTariffTable] AS
	Select top 10000000000 
		siCommonTariff, TariffName, Price, Type, TebService, IsAfter, Countable, Comment, Disabled, SeqNO, ExtraPercent, ForceExtra		
	 From CommonTariffTable
	order by SeqNO 
GO

/****** Object:  View [dbo].[VW_Default_Angle]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







CREATE VIEW [dbo].[VW_Default_Angle]
AS
SELECT     TOP 100 PERCENT
	siDefault, defCode, DefalutName
FROM         DefaultTable
WHERE defCode = 1
ORDER BY DefalutName









GO

/****** Object:  View [dbo].[VW_Default_Assur]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE VIEW [dbo].[VW_Default_Assur]
AS
SELECT     TOP 100 PERCENT
	siDefault, defCode, DefalutName
FROM         DefaultTable
WHERE defCode = 2
ORDER BY DefalutName



GO

/****** Object:  View [dbo].[VW_Default_Doctors]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Default_Doctors] AS    
 SELECT     TOP 10000000    
  'RW'=ROW_NUMBER() OVER(order by LName,FName,siDoctors),
   siDoctors, FileID, FName, LName,Job,IsTebDoc,  
   Address1, Address2, Address3, Address4, Comment, Tag1, Tag2, Tag3, Tag4,    
   PerDiscount,SumAfter,FolderName, MedicalID,    
  'DoctorName' =  LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') )) ,  
  'FullName'   =  LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') )) +'  -  '+ Cast(FileID as varchar(10))+'  -  '+Job,  
  'Full_Name'  =  LTrim(RTrim( ISNULL(FName,'') +'  '+ ISNULL(LName,'') )) +'  -  '+ Cast(FileID as varchar(10))+'  -  '+Job      
 FROM    DoctorsTable  
 Where IsTebDoc =1  
 ORDER BY  RW 
GO

/****** Object:  View [dbo].[VW_Default_Doctors_ALL]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Default_Doctors_ALL] AS    
 SELECT     TOP 10000000    
  'RW'=ROW_NUMBER() OVER(order by LName,FName,siDoctors),
   siDoctors, FileID, FName, LName,Job,IsTebDoc,  
   Address1, Address2, Address3, Address4, Comment, Tag1, Tag2, Tag3, Tag4,    
   PerDiscount,SumAfter,FolderName, MedicalID,    
  'DoctorName' =  LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') )) ,  
  'FullName'   =  LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') )) +'  -  '+ Cast(FileID as varchar(10))+'  -  '+Job,  
  'Full_Name'  =  LTrim(RTrim( ISNULL(FName,'') +'  '+ ISNULL(LName,'') )) +'  -  '+ Cast(FileID as varchar(10))+'  -  '+Job      
 FROM    DoctorsTable    
 ORDER BY  RW  
GO

/****** Object:  View [dbo].[VW_Default_Hospitals]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW  [dbo].[VW_Default_Hospitals] AS    
 SELECT  TOP 10000000000    
  siHospital, FullName, Type, Comment, Location, ForceAfter   
 FROM    HospitalTable    
 ORDER BY  SeqNO ,FullName    
GO

/****** Object:  View [dbo].[VW_Default_Surg]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







CREATE VIEW [dbo].[VW_Default_Surg]
AS
SELECT     TOP 100 PERCENT
	siDefault, defCode, DefalutName
FROM         DefaultTable
WHERE defCode = 0
ORDER BY DefalutName









GO

/****** Object:  View [dbo].[VW_Get_ListOfSurgery]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO








CREATE View [dbo].[VW_Get_ListOfSurgery] AS 
SELECT AST.siAlbum, AST.siSurgery, ST.SurgeryName, ST.Sequent, ST.Show
FROM   AlbumSurgTable AST 
LEFT OUTER JOIN  SurgeryTable  ST   
             ON  AST.siSurgery = ST.siSurgery
WHERE ST.Show = '1'








GO

/****** Object:  View [dbo].[VW_Get_Surgery]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE View [dbo].[VW_Get_Surgery] AS 
 Select  Top 100 Percent
	siSurgery,SurgeryName,LatinName,Sequent,Show
 From SurgeryTable 
 where Show = 1
 Order By Sequent







GO

/****** Object:  View [dbo].[VW_GetCount_TypesTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE View [dbo].[VW_GetCount_TypesTable] AS 
 Select Count(*) AS Number From TypesTable







GO

/****** Object:  View [dbo].[VW_GetFilesInfo_noPhoto]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  View [dbo].[VW_GetFilesInfo_noPhoto] AS   
 Select    
 siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter ,BirthYear,ReferDate,siHospital,  
 Subject,Comment,Address,Age,SendType,DoctorName,Job,RefFileID  
 From FilesTable    
GO

/****** Object:  View [dbo].[VW_GetNewFileID]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE View [dbo].[VW_GetNewFileID] AS
  select 'NewID' = ISNULL(Max(FileID),1000)+1 from FilesTable







GO

/****** Object:  View [dbo].[VW_Select_AccountTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_AccountTable] AS 
 Select  
	siAccount,siFiles,siDiscount,PerDiscount,Discount,TotalPrice,PayableFee,
	PaidAmount,RemainAmount,PaidDate,Type,Comment
 From AccountTable

GO

/****** Object:  View [dbo].[VW_Select_AlbumSurgTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








-----------------------------------------------------

Create View [dbo].[VW_Select_AlbumSurgTable] AS 
 Select  
	siAlbumSurg,siAlbum,siSurgery
 From AlbumSurgTable







GO

/****** Object:  View [dbo].[VW_Select_AlbumTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








-----------------------------------------------------

CREATE View [dbo].[VW_Select_AlbumTable] AS 
 Select  
	siAlbum,siFiles,AlbumName,AlbumDate,SurgDate,Comment
 From AlbumTable








GO

/****** Object:  View [dbo].[VW_Select_ALL_FileID]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE View [dbo].[VW_Select_ALL_FileID] AS   
 Select siFiles,FileID From FilesTable  




GO

/****** Object:  View [dbo].[VW_SELECT_All_Files_Tarrif]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_SELECT_All_Files_Tarrif] AS
	SELECT 
		HT.siHospital, FullName, Type, Location, HT.ForceAfter H_ForceAfter,  
		HT.ConstantBefor H_ConstantBefor, HT.PercentBefor H_PercentBefor, HT.LimmitBefor H_LimmitBefor, 
		HT.ConstantAfter H_ConstantAfter, HT.PercentAfter H_PercentAfter, HT.LimmitAfter H_LimmitAfter, 
		HT.Comment H_Comment, 
		siPrivateTariff, PT.ForceAfter D_ForceAfter,
		PT.ConstantBefor D_ConstantBefor, PT.PercentBefor D_PercentBefor, PT.LimmitBefor D_LimmitBefor, 
		PT.ConstantAfter D_ConstantAfter, PT.PercentAfter D_PercentAfter, PT.LimmitAfter D_LimmitAfter, 
		PT.Comment D_Comment,
		siFiles, siDoctor, FileID, FName, LName, Phone1,Phone2, RefPlace, 
		PaidAfter, BirthYear, ReferDate, Subject, FT.Comment F_Comment, 
		Address, Age, SendType, DoctorName, Job, RefFileID, Bef_Aft, Sex

	FROM FilesTable FT
	INNER JOIN HospitalTable HT ON FT.siHospital = HT.siHospital
	LEFT  JOIN PrivateTariffTable PT ON FT.siDoctor = PT.siDoctors 
GO

/****** Object:  View [dbo].[VW_SELECT_All_Statistics]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  VIEW [dbo].[VW_SELECT_All_Statistics] AS  
SELECT  
 siFiles, P_FileID, PatientName, DoctorName, Job, FullName, ReferDate, SurgDate, WaitTime, WaitTimeOut,   
 Subject, SUM(Number) TotalNumber, Bef_Aft, HasPrivateTariffCost,   
 PaidAfter, PreCost, SendType, D_PerDiscount,SumAfter,
 PayableFee, PaidAmount, RemainAmount, Discount, PaidDate, Comment, RoundAmount, Title, PerDiscount  
 FROM(  
  SELECT DISTINCT    
   FT.siFiles, FT.FileID AS P_FileID,   
   'PatientName'=FT.LName+' '+ ISNULL(FT.FName,''), 'DoctorName'=DT.LName+' '+ ISNULL(DT.FName,''),  
   DT.Job,HT.FullName,ReferDate,AT.SurgDate,WT.WaitTime,WT.WaitTimeOut,Subject,ST.Number,  
   'Bef_Aft'= Case when Bef_Aft= 0 then 'Before' else 'After' end,   
   'HasPrivateTariffCost' = CASE WHEN PT.siPrivateTariff IS NULL THEN  'عمومی'  ELSE 'ثابت' END ,      
   'PaidAfter' =Case When PaidAfter = 1 then 'در یافت مبلغ AFTER' else NULL  end,   
   'PreCost' = ( SELECT Count(*) FROM FilesTable FT2 WHERE FT2.FileID = FT.RefFileID AND FT2.PaidAfter = 1 AND FT.Bef_Aft = 1 ),    
   'SendType'= Case when SendType= 0 then 'اورژانس' else 'عادی' end ,     
   DT.PerDiscount AS D_PerDiscount,  
   DT.SumAfter,PayableFee,  
   ACT.PaidAmount,ACT.RemainAmount,  
   ACT.Discount,ACT.PaidDate,ACT.Comment,ACT.RoundAmount,  
   DCT.Title,DCT.PerDiscount  
     
  FROM   FilesTable FT    
  INNER JOIN   DoctorsTable DT ON FT.siDoctor = DT.siDoctors    
  INNER JOIN   AlbumTable AT ON AT.siFiles = FT.siFiles    
  INNER JOIN   HospitalTable HT ON FT.siHospital = HT.siHospital    
  LEFT  JOIN   PrivateTariffTable PT ON DT.siDoctors = PT.siDoctors    
  LEFT  JOIN   WaitTable WT  ON FT.siFiles = WT.siFiles    
  LEFT  JOIN   ServiceTable ST ON ST.siFiles = FT.siFiles   
  LEFT  JOIN   AccountTable ACT ON ACT.siFiles = FT.siFiles  
  LEFT  JOIN   DiscountTable DCT ON DCT.siDiscount = ACT.siDiscount  
) A  
/* WHERE siFiles IN (2539,3115,6669,11418,10833,11420,11345,10967) */  
GROUP BY   
 siFiles, P_FileID, PatientName, DoctorName, Job, FullName, ReferDate, SurgDate, WaitTime, WaitTimeOut,   
 Subject, Bef_Aft,HasPrivateTariffCost, PaidAfter, PreCost, SendType, D_PerDiscount, 
 SumAfter,PayableFee,PaidAmount, RemainAmount, Discount, PaidDate, Comment, RoundAmount, Title, PerDiscount  
 
GO

/****** Object:  View [dbo].[VW_SELECT_All_Tarrif]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
CREATE VIEW [dbo].[VW_SELECT_All_Tarrif] AS  
 SELECT   
  siFiles, Location, FullName  
  ,CASE   
   When Location = 0 then HT.ForceAfter  
   When Location = 1 then PT.ForceAfter  
   END as ForceAfter  
  ,CASE   
   When Location = 0 and HT.ConstantBefor IS NOT NULL then 'C'  
   When Location = 0 and HT.PercentBefor  IS NOT NULL then 'P'  
   When Location = 0 and HT.LimmitBefor   IS NOT NULL then 'L'  
   When Location = 1 and PT.ConstantBefor IS NOT NULL then 'C'  
   When Location = 1 and PT.PercentBefor  IS NOT NULL then 'P'  
   When Location = 1 and PT.LimmitBefor   IS NOT NULL then 'L'  
   END TarrifBeforeType  
  ,CASE   
   When Location = 0 and HT.ConstantAfter IS NOT NULL then 'C'  
   When Location = 0 and HT.PercentAfter  IS NOT NULL then 'P'  
   When Location = 0 and HT.LimmitAfter   IS NOT NULL then 'L'  
   When Location = 1 and PT.ConstantAfter IS NOT NULL then 'C'  
   When Location = 1 and PT.PercentAfter  IS NOT NULL then 'P'  
   When Location = 1 and PT.LimmitAfter   IS NOT NULL then 'L'  
   END TarrifAfterType  
  ,CASE Location  
   When 0 then COALESCE(HT.ConstantBefor, HT.PercentBefor, HT.LimmitBefor)  
   When 1 then COALESCE(PT.ConstantBefor, PT.PercentBefor, PT.LimmitBefor)  
   END as AmountBefore  
  ,CASE Location  
   When 0 then COALESCE(HT.ConstantAfter, HT.PercentAfter, HT.LimmitAfter)  
   When 1 then COALESCE(PT.ConstantAfter, PT.PercentAfter, PT.LimmitAfter)  
   END as AmountAfter  
  ,CASE WHEN  
   ( Location = 0 and HT.ConstantBefor IS NOT NULL ) OR  
   ( Location = 0 and HT.PercentBefor  IS NOT NULL ) OR  
   ( Location = 0 and HT.LimmitBefor   IS NOT NULL ) OR  
   ( Location = 1 and PT.ConstantBefor IS NOT NULL ) OR  
   ( Location = 1 and PT.PercentBefor  IS NOT NULL ) OR  
   ( Location = 1 and PT.LimmitBefor   IS NOT NULL ) OR  
   ( Location = 0 and HT.ConstantAfter IS NOT NULL ) OR  
   ( Location = 0 and HT.PercentAfter  IS NOT NULL ) OR  
   ( Location = 0 and HT.LimmitAfter   IS NOT NULL ) OR  
   ( Location = 1 and PT.ConstantAfter IS NOT NULL ) OR  
   ( Location = 1 and PT.PercentAfter  IS NOT NULL ) OR  
   ( Location = 1 and PT.LimmitAfter   IS NOT NULL ) then 1  
   END HasTarrif  
 ,PaidAfter,SendType,Bef_Aft,FileID    
 ,'PreCost' =( SELECT NULLIF( Count(*),0 )   
     FROM FilesTable FT2   
     WHERE FT2.FileID = FT.RefFileID AND FT2.PaidAfter = 1 AND FT.Bef_Aft = 1   
    )  
   
 FROM FilesTable FT  
 INNER JOIN HospitalTable HT ON FT.siHospital = HT.siHospital  
 LEFT  JOIN PrivateTariffTable PT ON FT.siDoctor = PT.siDoctors   
  
-- Bef_Aft  { 0 is Before else 1 is After }  
-- SendType { 0 is اورژانس else 1 عادي   
GO

/****** Object:  View [dbo].[VW_Select_AllPatients_Without_Thumb]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_AllPatients_Without_Thumb] AS         
 Select top 100 percent      
   siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Bef_Aft,siHospital,      
   Subject,Comment,Address,Age,SendType,DoctorName,Job, RefFileID,siDoctor,      
  'FullName' = LTrim(RTrim(ISNULL(LName,'') +'  '+FName)) ,       
  'Ref' = Case when RefFileID = FileID then NULL else Cast(RefFileID as varchar(10)) end  ,    
  'After' = Case when PaidAfter = 1 then 'دريافت شد' else '' end ,Sex
 From FilesTable        
 order by  LName,FName,RefFileID,FileID      

GO

/****** Object:  View [dbo].[VW_Select_BoxInfoTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

CREATE View [dbo].[VW_Select_BoxInfoTable] AS 
 Select  
	siBoxInfo,siPage,Type,Grp,Xmargin,Ymargin,Status
 From BoxInfoTable






GO

/****** Object:  View [dbo].[VW_Select_CommonTariffTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create View [dbo].[VW_Select_CommonTariffTable] AS 
 Select  
	siCommonTariff,TariffName,Price,Type,IsAfter,Countable,Comment
 From CommonTariffTable

GO

/****** Object:  View [dbo].[VW_Select_CommonTariffTable_NoTEB]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE VIEW [dbo].[VW_Select_CommonTariffTable_NoTEB] AS  
SELECT 
  SeqNO, siCommonTariff, TariffName, Price, Type, IsAfter,  Countable, Comment  
 FROM   CommonTariffTable   
 WHERE Type = 0 and Disabled IS NULL
GO

/****** Object:  View [dbo].[VW_Select_CommonTariffTable_TEB]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  VIEW [dbo].[VW_Select_CommonTariffTable_TEB] AS    
 SELECT TOP 100 PERCENT     
  siCommonTariff, TariffName, Price, Type, IsAfter,  Countable, Comment    
 FROM   CommonTariffTable     
 WHERE Type = 1    
GO

/****** Object:  View [dbo].[VW_Select_CommonTariffTableType2]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  VIEW [dbo].[VW_Select_CommonTariffTableType2] AS      
 SELECT TOP 100 PERCENT       
  siCommonTariff, TariffName, Price, Type, IsAfter,  Countable, Comment      
 FROM   CommonTariffTable       
 WHERE Type = 2      
  
GO

/****** Object:  View [dbo].[VW_Select_DoctorsTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create View [dbo].[VW_Select_DoctorsTable] AS 
 Select  
	siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4
 From DoctorsTable

GO

/****** Object:  View [dbo].[VW_Select_DoctorsTable_Full]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_DoctorsTable_Full] AS   

 Select TOP 10000000000

 siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4,  

 'FullName'= ISNULL(LName,'')+' '+ISNULL(FName,'')+' ('+Job+')'+ CAST(FileID as varchar(10)),

 EMail1,EMail2,SMS1,SMS2,IsActiveEMail,IsActiveSMS  

 From DoctorsTable  

 ORDER BY FullName

GO

/****** Object:  View [dbo].[VW_Select_DocumentTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_DocumentTable] AS 
 Select  
	siDocument,siAlbum,TypeNumber,Title,DocumentDate,Path,Document,SumCode,PathOrDoc,Comment,ISNULL(siPage,0) as siPage,ISNULL(CheckValue,0) as CheckValue
 From DocumentTable
GO

/****** Object:  View [dbo].[VW_Select_FilesTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_FilesTable] AS       
Select top 100 percent    
  siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,thumb,Bef_Aft,siHospital,Comment,    
  Address,Age,SendType,DoctorName,Job, RefFileID ,'FullName' = LTrim(RTrim(ISNULL(FName,'') +'  '+LName))  ,Sex, PathFolder
 From FilesTable      
order by  FileID    
 
GO

/****** Object:  View [dbo].[VW_Select_FilesTable_ForFiles]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_FilesTable_ForFiles] AS      
 Select    TOP  100 Percent   
  siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,siHospital,Comment,  
  Address,Age,SendType,DoctorName,Job, RefFileID,  
  'AllName' =LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,'PaidAfterStatus'= Case PaidAfter when 0 then NULL else 'پرداخت شد' end    
 From FilesTable      
 ORDER BY FileID DESC   
  
GO

/****** Object:  View [dbo].[VW_Select_FilesTable_Without_Thumb]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_FilesTable_Without_Thumb] AS         
 Select top 100 percent      
   siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Bef_Aft,siHospital,      
   Subject,Comment,Address,Age,SendType,DoctorName,Job, RefFileID,siDoctor,PathFolder, 
   'FullName' = LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') ))  ,
   'Full_NamePatient' = LTrim(RTrim( ISNULL(FName,'') +'  '+ ISNULL(LName,'') )) , Sex  
 From FilesTable        
order by  FileID      
GO

/****** Object:  View [dbo].[VW_Select_FilesTable_WithThumb]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_FilesTable_WithThumb] AS      
 Select    TOP  100 Percent   
  siFiles,FileID,FName,LName,Phone1,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,    
  thumb,  
  Comment,Address,Age,SendType,DoctorName,Job,RefFileID,  
  'AllName' =LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,'PaidAfterStatus'= Case PaidAfter when 0 THEN NULL else 'PaidAfter' end    
 From FilesTable      
 ORDER BY FileID DESC    
 
GO

/****** Object:  View [dbo].[VW_Select_ListOfSergery_Test]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_ListOfSergery_Test] AS
	SELECT   
		FT.siFiles , FT.siDoctor, LTRIM(RTRIM(ST.SurgeryName)) as SurgeryName
		,REPLACE(REPLACE( SurgeryName , NCHAR(1705), NCHAR(1603)),NCHAR(1740),NCHAR(1610) ) as SurgeryNameUTF
	FROM  FilesTable FT 
	INNER JOIN AlbumTable AL ON FT.siFiles = AL.siFiles
	INNER JOIN AlbumSurgTable ALS ON ALS.siAlbum = AL.siAlbum
	INNER JOIN SurgeryTable ST ON ST.siSurgery = ALS.siSurgery
GO

/****** Object:  View [dbo].[VW_Select_PageTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_Select_PageTable] AS 
 Select  
	siPage,CheckCount,TitlePage,PagePhoto
 From PageTable
GO

/****** Object:  View [dbo].[VW_Select_PageTable_NoPhoto]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

Create View [dbo].[VW_Select_PageTable_NoPhoto] AS 
 Select  
	siPage,CheckCount,TitlePage
 From PageTable



GO

/****** Object:  View [dbo].[VW_Select_ServiceTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE View [dbo].[VW_Select_ServiceTable] AS 
 Select  
	siServiceTable,siFiles,siWait,siCommonTariff,Number,Type
 From ServiceTable




GO

/****** Object:  View [dbo].[VW_Select_SurgeryTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE View [dbo].[VW_Select_SurgeryTable] AS 
 Select  Top 100 Percent
	siSurgery,SurgeryName,LatinName,Sequent,Show
 From SurgeryTable 
 Order By SurgeryName











GO

/****** Object:  View [dbo].[VW_Select_SurgList]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








Create view [dbo].[VW_Select_SurgList] AS
select siSurgery,SurgeryName from SurgeryTable







GO

/****** Object:  View [dbo].[VW_Select_System]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





Create View [dbo].[VW_Select_System] AS
SELECT     siSystem, P1, P2  FROM SystemTable




GO

/****** Object:  View [dbo].[VW_Select_TypesTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE View [dbo].[VW_Select_TypesTable] AS 
 Select  TOP 100 percent
	siTypes,Number,Type
 From TypesTable
 order by siTypes











GO

/****** Object:  View [dbo].[VW_Select_Users]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







CREATE View [dbo].[VW_Select_Users] AS
SELECT  siUser, UserName, [Password], IsAdmin
FROM UserTable






GO

/****** Object:  View [dbo].[VW_Select_UserTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW  [dbo].[VW_Select_UserTable] AS
	SELECT  TOP  100 PERCENT    
		siUser, UserName, Password, IsAdmin, @@SPID SPID, GetDATE() as LoginDate 
	FROM         UserTable
	order by  UserName
GO

/****** Object:  View [dbo].[VW_Select_WaitList_Doc_Hospital]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_Select_WaitList_Doc_Hospital] AS  
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 SELECT           
  siWait, WT.siFiles, WaitDate, WaitTime,WaitCall,WaitPhoto,WaitService,WaitTimeOut,Phone1,Phone2,ReferDate,BEF_AFT,
  MachinePhoto, SurgStatus, Status,SendType, ISNULL(FT.IsScanned,-1) as IsScanned, FT.FileID as PatientFiledId,          
  'SG_Status' = CASE SurgStatus WHEN 0 THEN 'Before' ELSE 'AFTER' END ,           
  'WaitStatus' = CASE Status           
     WHEN  1 THEN 'ثبت شد'           
     WHEN  2 THEN 'چک شد'           
     WHEN  4 THEN 'عکسبرداري شد'           
     WHEN  8 THEN 'خدمات تعيين شد'           
     WHEN 16 THEN 'تسويه حساب شد'           
    END ,           
  'SendStatus' = CASE SendType           
     WHEN 0 THEN 'اورژانس'           
     WHEN 1 THEN 'عادي'           
    END ,           
  ISNULL(FT.LName,'') PLName,
  ISNULL(FT.FName,'') PFName,
  'PatientName'=  ISNULL(FT.LName,'') +' '+ ISNULL(FT.FName,'') , Subject,DT.siDoctors, DT.FileID,  
  'DoctorName2'=ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,''),          
  'DoctorName'=ISNULL(DT.LName,'') +' '+ ISNULL(DT.FName,''), 
  DT.Description,         
  HT.FullName,Edited,Printed, BT.siBranch, BT.BranchName, WT.WaitCheck, WT.MachineCheck,
  WT.SentEMail,WT.EMailDate,WT.EMailTime, CAST( TD2.Miladi+' '+ WT.EMailTime as Datetime) as SentEMailTime,
  WT.AttachedCount, WT.AttachedCountTeleg,WT.SentSMS, FactorStatus, 
  TelegramStatus, TelegMessageId, TryCount, SendDate, ManualTelegDate, TD.Shamsi as  ManualTelegDateS,
  
  NULLIF(LTRIM(RTRIM(DT.EMail1)),'') EMail1, 
  NULLIF(LTRIM(RTRIM(DT.EMail2)),'') EMail2, 
  NULLIF(LTRIM(RTRIM(DT.IsActiveEMail)),'') IsActiveEMail, 
  NULLIF(LTRIM(RTRIM(DT.SMS1)),'') SMS1, 
  NULLIF(LTRIM(RTRIM(DT.SMS2)),'') SMS2, 
  NULLIF(LTRIM(RTRIM(DT.IsActiveSMS)),'') IsActiveSMS,
  NULLIF(LTRIM(RTRIM(DT.TelegramTeb)),'') TelegramTeb, 
  NULLIF(LTRIM(RTRIM(DT.IsActiveTelegTeb)),'') IsActiveTelegTeb,
 
  ISNULL(IsAuto,0) as IsAuto,
  FT.HasFilterList,
  Filter, ManualTelegStatus,
  'AutoOrManual' = IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),'A','M') 
  ,Is3D
  ,Case When Edited IS NULL then 1 else 0 end as IsFirstPrint
  FROM WaitTable WT with(nolock)         
  INNER JOIN FilesTable FT with(nolock)  ON FT.siFiles = WT.siFiles          
  INNER JOIN DoctorsTable DT  ON FT.siDoctor = DT.siDoctors          
  INNER JOIN HospitalTable HT  ON FT.siHospital = HT.siHospital           
  INNER JOIN BranchTable BT ON BT.siBranch = FT.siBranch
  LEFT  JOIN TblDate  TD ON TD.MiladiDate = Cast( ManualTelegDate as DATE)
  LEFT  JOIN TblDate  TD2 ON TD2.Shamsi = WT.EMailDate
 
GO

/****** Object:  View [dbo].[VW_Select_WaitTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

CREATE View [dbo].[VW_Select_WaitTable] AS 
 Select  
	siWait,siFiles,WaitDate,WaitTime,WaitTimeOut,SurgStatus,Status,Comment
 From WaitTable


GO

/****** Object:  View [dbo].[VW_SelectIconsForDesign]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_SelectIconsForDesign] AS
SELECT     TOP 100 PERCENT siIcon, IconName, IconThumb
FROM         dbo.IconTable
WHERE IconName Like 'FormPages%'
ORDER BY siIcon
GO

/****** Object:  View [dbo].[VW_SYS_LogAccounts]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE View [dbo].[VW_SYS_LogAccounts] AS
	with cte as 
	(
		Select 
			siAccount,siFiles,siDiscount,PerDiscount,Discount,TotalPrice,PayableFee,PaidAmount,RemainAmount,RoundAmount,PaidDate,Type,Comment,FactorDate,DiscountTitle,T_F,T_O,T_B,T_A,Used_Location,Use_Bef_Aft,Used_PreCost,Used_PaidAfter,Used_SendType,Used_BefTariff,Used_BefAmount,Used_AftTariff,Used_AftAmount,IsExtra,NULL LogDateTime,'Issued' LogType
		from AccountTable 
		where siFiles in( Select siFiles From LogAccountTable)
		union 
		Select 
			siAccount,siFiles,siDiscount,PerDiscount,Discount,TotalPrice,PayableFee,PaidAmount,RemainAmount,RoundAmount,PaidDate,Type,Comment,FactorDate,DiscountTitle,T_F,T_O,T_B,T_A,Used_Location,Use_Bef_Aft,Used_PreCost,Used_PaidAfter,Used_SendType,Used_BefTariff,Used_BefAmount,Used_AftTariff,Used_AftAmount,IsExtra, LogDateTime,LogType
		from LogAccountTable LT with(nolock) 
		--where siAccount > 957980
	)
	Select Top 100000000
		Ft.FName, FT.LName, A.* from Cte A
	inner join FilesTable FT ON A.siFiles = FT.siFiles
	where FT.ReferDate >='1397/01/01'
	order by A.siFiles desc , siAccount desc 

GO

/****** Object:  View [dbo].[VW_SYS_LogServiceTable]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   View [dbo].[VW_SYS_LogServiceTable] AS
with  cte as 
(
	Select 0 as siAccount,siFiles,siWait,siCommonTariff,Number,Type,UsedTariffName,UsedPrice from ServiceTable 
	where siFiles in(Select siFiles from LogServiceTable)
	union
	Select siAccount,siFiles,siWait,siCommonTariff,Number,Type,UsedTariffName,UsedPrice from LogServiceTable 
)
Select top  1000000000
	FT.FName, FT.LName,FT.FileID, FT.ReferDate,A.* from Cte  A 
Inner join FilesTable Ft ON ft.siFiles = A.sifiles 
where FT.ReferDate >='1397/01/01'
order by FT.siFiles desc , CASE siAccount When 0 then 999999999999 else siAccount end desc 

GO

/****** Object:  View [dbo].[VW_SYS_WaitFiles]    Script Date: 7/26/2020 2:54:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[VW_SYS_WaitFiles] AS
SELECT TOP 10000000
	FName , LName, DoctorName,
	siWait, WT.siFiles, WaitDate, WaitTime, WaitTimeOut, 
	SurgStatus, Status, 
	WaitCheck, WaitCall, WaitPhoto, WaitService, MachineCheck, MachinePhoto, 
	Edited, Printed, SentEMail, EMailDate, EMailTime, AttachedCount, 
	SentSMS, SentSMSTime, FactorStatus, SentSMSLAB, SentSMSTimeLAB
FROM WaitTable WT 
INNER JOIN FilesTable FT ON FT.siFiles = WT.siFiles
ORDER BY siWait DESC 
GO


