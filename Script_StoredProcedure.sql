USE [CosmoSample]
GO

/****** Object:  StoredProcedure [dbo].[USP_CancelCalculation]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_CancelCalculation](@siAccount int, @LogType varchar(50)) AS  
BEGIN  
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
	DECLARE @siFiles int, @is3d tinyint; 
 
	SELECT @siFiles = siFiles FROM AccountTable WHERE siAccount = @siAccount
	Select @is3d= Is3D from FilesTable Where siFiles = @siFiles
 
	EXEC USP_CreateLogForAccount @siAccount ,@LogType  
 
	DELETE AccountTable WHERE siAccount = @siAccount  
	 
	IF @is3d=1 
	BEGIN
		IF EXISTS(SELECT * FROM Wait3DTable WHERE siFiles = @siFiles AND Status = 16 ) 
			EXEC USP_Set3DWait_Status  @siFiles, 16,1
			--UPDATE WaitTable SET  Status = 8 Where siFiles = @siFiles	

	END

	UPDATE WaitTable SET  Status = 8 Where siFiles = @siFiles
END  
 
GO

/****** Object:  StoredProcedure [dbo].[USP_CancelCalculationExtra]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_CancelCalculationExtra](@siAccount int, @LogType varchar(50)) AS    
BEGIN    
 EXEC USP_CreateLogForAccountExtra @siAccount ,@LogType    
 Delete AccountTable WHERE siAccount = @siAccount    
END 
GO

/****** Object:  StoredProcedure [dbo].[USP_CheckEMailTelegramForPatient]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_CheckEMailTelegramForPatient]( @siFiles int ) AS
BEGIN

	DECLARE @siWaitForEmail int=0 , @siWaitForTeleg int =0;
		 SELECT               
		   @siWaitForEmail =IIF(ISNULL(HPT.IsActiveEMail,0) = 1 ,siWait,0),
		   @siWaitForTeleg =IIF(ISNULL(HPT.IsActiveTelegTeb,0) = 1 ,siWait,0)
		 FROM  VW_Select_WaitList_Doc_Hospital HPT 
		 INNER JOIN AlbumTable ALT ON HPT.siFiles = ALT.siFiles
		 WHERE 
			  HPT.siFiles = @siFiles  AND  
			  ( Status = 16 ) AND
			  ISNULL(Printed,0)=1 AND 
			  ISNULL(Edited,0)=1 			  

	SELECT @siWaitForEmail as siWaitForEmail, @siWaitForTeleg as siWaitForTeleg
END 
GO

/****** Object:  StoredProcedure [dbo].[USP_CloseOpenedFiles]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_CloseOpenedFiles]( @Path nvarchar(4000), @OLdPath nvarchar(4000)) AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY DROP TABLE #T END TRY BEGIN CATCH END CATCH
 
	DECLARE @Ret int, @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	EXEC xp_cmdshell N'del C:\"Tebnegar Network Opened Files Service"\netOpenedFiles.xml'
	
FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC xp_cmdshell N'C:\"Tebnegar Network Opened Files Service"\NOFC.bat /list'
 
	DECLARE @I INT=1, @ReadError bit =0
	DECLARE  @MyPath1 nvarchar(4000) = STUFF(@Path,1, Charindex('$', @Path )+1,'') 
	
	DECLARE  @MyPath2 nvarchar(4000) = STUFF(@OLdPath,1, Charindex('$', @OLdPath )+1,'') 
	SET @MyPath2 = IIF(ISNULL(@MyPath2,'') ='','!!!!',@MyPath2)
 
	DECLARE @XML as XML ; 
	WHILE @I <= 5
	BEGIN
		BEGIN TRY
			WAITFOR DELAY '00:00:01'
			SELECT @XML =CONVERT(xml, BulkColumn, 2) 
			FROM   OPENROWSET(Bulk 'C:\\Tebnegar Network Opened Files Service\\netOpenedFiles.xml', SINGLE_BLOB) XmlData
			SET @ReadError =0
			BREAK
		END TRY
		BEGIN CATCH
			SET @ReadError =1
		END CATCH
		SET @I += 1
	END
 
	IF EXISTS (Select TraceEnables from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
	IF @ReadError =1 
		RETURN -1	 
 
	;WITH CTE AS
	(
	Select  
		fld.value('filename[1]','nvarchar(1000)') as FileName,
		LTRIM(RTRIM(fld.value('file_extension[1]','nvarchar(1000)'))) as Ext,		
		fld.value('user[1]','nvarchar(1000)') as UserName,
		fld.value('computer[1]','nvarchar(1000)') as Computer,
		fld.value('host_name[1]','nvarchar(1000)') as HostName,
		fld.value('filename_only[1]','nvarchar(1000)') as FilenameOnly,
		fld.value('id[1]','nvarchar(1000)') as IDHex 
	From @Xml.nodes('network_files_list/item')Tbl(fld)
	)
	SELECT 
		*,
		CONVERT(BIGINT, CONVERT(VARBINARY, IDHex, 1)) as FID,
		CONCAT('EXEC xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /close ',CONVERT(BIGINT, CONVERT(VARBINARY, IDHex, 1) ),'''') as cmd
	INTO #T
	FROM CTE 
	
	if (Select count(*) from #T WHERE FileName like '%'+@MyPath1+'%' OR FileName like '%'+@MyPath2+'%') =0 
		RETURN 0
	
	DECLARE @cmd nvarchar(1000) 	
	
	DECLARE cr_OpenedFiles CURSOR  FOR 
		SELECT cmd FROM #T WHERE FileName like '%'+@MyPath1+'%'  OR FileName like '%'+@MyPath2+'%'
	OPEN  cr_OpenedFiles
	FETCH NEXT FROM cr_OpenedFiles INTO @cmd 
	WHILE @@FETCH_STATUS = 0  
	BEGIN  
		EXEC( @cmd ) 
		FETCH NEXT FROM cr_OpenedFiles INTO @cmd 
		Print @cmd 
	END  
  
	CLOSE cr_OpenedFiles  
	DEALLOCATE cr_OpenedFiles  
 
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U2'
 
	WAITFOR DELAY '00:00:01'
	BEGIN TRY DROP TABLE #T END TRY BEGIN CATCH END CATCH
	RETURN 0
 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_CloseOpenedFiles_Pre]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_CloseOpenedFiles_Pre]( @Path nvarchar(4000), @OLdPath nvarchar(4000)) AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY DROP TABLE #T END TRY BEGIN CATCH END CATCH
 
	DECLARE @Ret int, @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	EXEC xp_cmdshell N'del C:\"Tebnegar Network Opened Files Service"\netOpenedFiles.xml'
	
FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC xp_cmdshell N'C:\"Tebnegar Network Opened Files Service"\NOFC.bat /list'
 
	DECLARE @I INT=1, @ReadError bit =0
	DECLARE  @MyPath1 nvarchar(4000) = STUFF(@Path,1, Charindex('$', @Path )+1,'') 
	
	DECLARE  @MyPath2 nvarchar(4000) = STUFF(@OLdPath,1, Charindex('$', @OLdPath )+1,'') 
	SET @MyPath2 = IIF(ISNULL(@MyPath2,'') ='','!!!!',@MyPath2)
 
	DECLARE @XML as XML ; 
	WHILE @I <= 5
	BEGIN
		BEGIN TRY
			WAITFOR DELAY '00:00:01'
			SELECT @XML =CONVERT(xml, BulkColumn, 2) 
			FROM   OPENROWSET(Bulk 'C:\\Tebnegar Network Opened Files Service\\netOpenedFiles.xml', SINGLE_BLOB) XmlData
			SET @ReadError =0
			BREAK
		END TRY
		BEGIN CATCH
			SET @ReadError =1
		END CATCH
		SET @I += 1
	END
 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
	IF @ReadError =1 
		RETURN -1	 
 
	;WITH CTE AS
	(
	Select  
		fld.value('filename[1]','nvarchar(1000)') as FileName,
		LTRIM(RTRIM(fld.value('file_extension[1]','nvarchar(1000)'))) as Ext,		
		fld.value('user[1]','nvarchar(1000)') as UserName,
		fld.value('computer[1]','nvarchar(1000)') as Computer,
		fld.value('host_name[1]','nvarchar(1000)') as HostName,
		fld.value('filename_only[1]','nvarchar(1000)') as FilenameOnly,
		fld.value('id[1]','nvarchar(1000)') as IDHex 
	From @Xml.nodes('network_files_list/item')Tbl(fld)
	)
	SELECT 
		*,
		CONVERT(BIGINT, CONVERT(VARBINARY, IDHex, 1)) as FID,
		CONCAT('EXEC xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /close ',CONVERT(BIGINT, CONVERT(VARBINARY, IDHex, 1) ),'''') as cmd
	INTO #T
	FROM CTE 
	
	if (Select count(*) from #T WHERE FileName like '%'+@MyPath1+'%' OR FileName like '%'+@MyPath2+'%') =0 
		RETURN 0
	
	DECLARE @cmd nvarchar(1000) 	
	
	DECLARE cr_OpenedFiles CURSOR  FOR 
		SELECT cmd FROM #T WHERE FileName like '%'+@MyPath1+'%'  OR FileName like '%'+@MyPath2+'%'
	OPEN  cr_OpenedFiles
	FETCH NEXT FROM cr_OpenedFiles INTO @cmd 
	WHILE @@FETCH_STATUS = 0  
	BEGIN  
		EXEC( @cmd ) 
		FETCH NEXT FROM cr_OpenedFiles INTO @cmd 
		Print @cmd 
	END  
  
	CLOSE cr_OpenedFiles  
	DEALLOCATE cr_OpenedFiles  
 
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U2'
 
	WAITFOR DELAY '00:00:01'
	BEGIN TRY DROP TABLE #T END TRY BEGIN CATCH END CATCH
	RETURN 0
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_CreateFolder]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_CreateFolder]( @FolderName nvarchar(500), @LoginName varchar(20) ) AS
BEGIN
	DECLARE @Script nvarchar(1000)='';
	DECLARE @ScriptGrant nvarchar(1000)=''
 	DECLARE @Grants nvarchar(4000);
 
	DECLARE @Ret int, @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
	
	SET @Script = N'xp_cmdshell N''MKDIR "'+@FolderName+'" ''' 
	SET @Grants  = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /grant "'+@FolderName+ '" Users''' 
 
 FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC( @Script )
	EXEC( @Grants )
 
	SET @Now = GETDATE() 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_CreateFolder_Pre]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_CreateFolder_Pre]( @FolderName nvarchar(500), @LoginName varchar(20) ) AS
BEGIN
	DECLARE @Script nvarchar(1000)='';
	DECLARE @ScriptGrant nvarchar(1000)=''
	DECLARE @Grants nvarchar(4000)=N'xp_cmdshell N''ICACLS "'+@FolderName+'"';
 
	SELECT @LoginName = LoginName FROM LoginGroup	WHERE IsGroup = 1
	SET @Grants  = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /grant "'+@FolderName+ '" '+@LoginName+'''' 
 
	DECLARE @Ret int, @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
	
	SET @Script = N'xp_cmdshell N''MKDIR "'+@FolderName+'" ''' 
 
 FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC( @Script )
	EXEC( @Grants )
 
	SET @Now = GETDATE() 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_CreateLogForAccount]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_CreateLogForAccount](@siAccount int,@LogType varchar(50)) AS      
BEGIN      
 DECLARE @siFiles int  
 SELECT @siFiles = siFiles FROM AccountTable WHERE siAccount = @siAccount
   
 INSERT INTO LogAccountTable(      
    siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount,   
    RemainAmount, RoundAmount, PaidDate, Type, Comment, PerDiscount,   
    Discount, FactorDate, DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft,   
    Used_PreCost, Used_PaidAfter, Used_SendType, Used_BefTariff,   
    Used_BefAmount, Used_AftTariff, Used_AftAmount, LogDateTime, LogType   
    )      
 SELECT      
    siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount,   
    RemainAmount, RoundAmount, PaidDate, Type, Comment, PerDiscount,   
    Discount, FactorDate, DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft,   
    Used_PreCost, Used_PaidAfter, Used_SendType, Used_BefTariff,   
    Used_BefAmount, Used_AftTariff, Used_AftAmount, GETDATE(), @LogType      
 FROM AccountTable       
 WHERE siAccount = @siAccount 
 --------------------------------------------------------------------------------  
 INSERT INTO LogServiceTable(   
    siAccount,siFiles, siWait, siCommonTariff, Number, Type, UsedTariffName, UsedPrice  
    )     
 SELECT    
  @siAccount,siFiles, siWait, siCommonTariff, Number, Type, UsedTariffName, UsedPrice  
 FROM ServiceTable   
 WHERE siFiles = @siFiles     
    
END;      
GO

/****** Object:  StoredProcedure [dbo].[USP_CreateLogForAccountExtra]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


--------------------------------------------------------------------------------    
CREATE PROC [dbo].[USP_CreateLogForAccountExtra](@siAccount int,@LogType varchar(50)) AS        
BEGIN        
 DECLARE @siFiles int    
 SELECT @siFiles = siFiles FROM AccountTable WHERE siAccount = @siAccount  
     
 INSERT INTO LogAccountTable(        
    siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount,     
    RemainAmount, RoundAmount, PaidDate, Type, Comment, PerDiscount,     
    Discount, FactorDate, DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft,     
    Used_PreCost, Used_PaidAfter, Used_SendType, Used_BefTariff,     
    Used_BefAmount, Used_AftTariff, Used_AftAmount, LogDateTime, LogType     
    )        
 SELECT        
    siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount,     
    RemainAmount, RoundAmount, PaidDate, Type, Comment, PerDiscount,     
    Discount, FactorDate, DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft,     
    Used_PreCost, Used_PaidAfter, Used_SendType, Used_BefTariff,     
    Used_BefAmount, Used_AftTariff, Used_AftAmount, GETDATE(), @LogType        
 FROM AccountTable         
 WHERE siAccount = @siAccount   

 INSERT INTO LogExtraServiceTable(     
     siAccount, siCommonTariff, FactorDate, Number, Type, UsedTariffName, UsedPrice    
    )       
 SELECT      
     siAccount, siCommonTariff, FactorDate, Number, Type, UsedTariffName, UsedPrice    
 FROM ExtraServiceTable    
 WHERE siAccount = @siAccount   
      
END;        
GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_AccountTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Delete_AccountTable](@siAccount int) AS 
Begin 
 Delete From AccountTable Where siAccount = @siAccount
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_AlbumSurgTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_AlbumSurgTable](@siAlbumSurg int) AS 
Begin 
 Delete From AlbumSurgTable Where siAlbumSurg = @siAlbumSurg
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_AlbumSurgTableByAlbum]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









Create Proc [dbo].[USP_Delete_AlbumSurgTableByAlbum](@siAlbum int) AS 
  Delete From AlbumSurgTable Where siAlbum = @siAlbum









GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_AlbumTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_AlbumTable](@siAlbum int) AS 
Begin 
 Delete From AlbumTable Where siAlbum = @siAlbum
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_BoxInfoTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

Create Proc [dbo].[USP_Delete_BoxInfoTable](@siBoxInfo int) AS 
Begin 
 Delete From BoxInfoTable Where siBoxInfo = @siBoxInfo
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_CommonTariffTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Delete_CommonTariffTable](@siCommonTariff  int) AS 
Begin 
 Delete From CommonTariffTable Where siCommonTariff = @siCommonTariff
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_DoctorsTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Delete_DoctorsTable](@siDoctors  int) AS 
Begin 
 Delete From DoctorsTable Where siDoctors = @siDoctors
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_DocumentTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_DocumentTable](@siDocument int) AS 
Begin 
 Delete From DocumentTable Where siDocument = @siDocument
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_FileReceiptTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Delete_FileReceiptTable] ( @siFiles int ) AS
BEGIN
	Delete FileReceiptTable 
	Where siFiles= @siFiles
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_FilesTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_FilesTable](@siFiles int) AS 
Begin 
 Delete From FilesTable Where siFiles = @siFiles
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_FilesTableInPatientBYFileID]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


Create Proc [dbo].[USP_Delete_FilesTableInPatientBYFileID]( @FileID int ) AS 
Begin 
 Delete From CosmoPatient.dbo.DoctorsTable Where FileID = @FileID
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_PageTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

Create Proc [dbo].[USP_Delete_PageTable](@siPage int) AS 
Begin 
 Delete From PageTable Where siPage = @siPage
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_ServiceTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Delete_ServiceTable](@siServiceTable  int) AS 
Begin 
 Delete From ServiceTable Where siServiceTable = @siServiceTable
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_ServiceTable_By_siFiles]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


Create Proc [dbo].[USP_Delete_ServiceTable_By_siFiles](@siFiles  int) AS 
Begin 
 Delete From ServiceTable Where siFiles = @siFiles
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_ServiceTable_ByWait]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Delete_ServiceTable_ByWait](@siWait  int ) AS     
Begin     
 Delete From ServiceTable Where siWait = @siWait 
End;    
GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_ServiceTable_Extra_siAccount]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Delete_ServiceTable_Extra_siAccount]( @siAccount  int ) AS     
Begin     
	Delete From ExtraServiceTable Where siAccount = @siAccount    
End;    
GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_SurgeryTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_SurgeryTable](@siSurgery int) AS 
Begin 
 Delete From SurgeryTable Where siSurgery = @siSurgery
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_TypesTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









-----------------------------------------------------

Create Proc [dbo].[USP_Delete_TypesTable](@siTypes int) AS 
Begin 
 Delete From TypesTable Where siTypes = @siTypes
End;








GO

/****** Object:  StoredProcedure [dbo].[USP_Delete_WaitTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Delete_WaitTable](@siWait  int) AS 
Begin 
 Delete From WaitTable Where siWait = @siWait
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_DeletedFiles_SetComplited]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_DeletedFiles_SetComplited]( @FileId int, @Mode Int) AS
BEGIN
	UPDATE DeletedFilesTable SET STATUS = @Mode WHERE FileID = @FileId 	
END
GO

/****** Object:  StoredProcedure [dbo].[USP_DeleteFolder]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE	PROCEDURE [dbo].[USP_DeleteFolder]( @FolderName nvarchar(1000), @LoginName varchar(20)) AS
BEGIN
	--@OldFolderName nvarchar(1000)='\\DBSERVER\Doctors4$\ابراهيم نژاد شقايق ENT 1586\ارسنجان مليحه 1030037048\ارسنجان مليحه 1030037048-Finl',
	--@NewFolderName nvarchar(1000)='\\DBSERVER\Doctors4$\ابراهيم نژاد شقايق ENT 1586\ارسنجان مليحه 1030037048\ارسنجان مليحه 1030037048-Final', 
 
 
	DECLARE @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	DECLARE @Script nvarchar(1000)=''
	SET @Script = N'xp_cmdshell N''rmdir /s /q "'+@FolderName+ '"''' 
 
	EXEC ( @Script )
 
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
END	
GO

/****** Object:  StoredProcedure [dbo].[USP_Deny_Permission]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[USP_Deny_Permission] ( @siFiles int, @LoginName varchar(20) ) AS
BEGIN
	if @LoginName in('quality','tebnegar') Return
	;WITH CTE AS
	(
		SELECT TOP 1  siPermission,ActionTime, DATEADD(Minute, -2, ActionTime ) NewActionTime FROM PermissionTable
		WHERE siFile = @siFiles  and LoginName = @LoginName
		ORDER BY ActionTime DESC
	)
	UPDATE CTE SET ActionTime = NewActionTime
 
	INSERT INTO PermissionTable (LoginName, Status,siFile,ScriptGrant,ScriptDeny,ActionTime,ErrorMessage )
	VALUES (@LoginName,'R', 0 ,N'Select 1 as a',N'Select 1 as a',Getdate(),NULL)
END
GO

/****** Object:  StoredProcedure [dbo].[USP_DenyPermissionFolder]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE	PROCEDURE [dbo].[USP_DenyPermissionFolder] ( @Path nvarchar(1000), @LoginName varchar(20) ) AS
BEGIN
	
	IF @Path ='' RETURN
 
	DECLARE @ScriptDeny nvarchar(1000)='';
 
	DECLARE @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	SET @ScriptDeny  = N'xp_cmdshell N''ICACLS "'+@Path+'" /remove '+@LoginName+' /T '''
	UPDATE PermissionTable SET Status = 'R' Where LoginName = @LoginName
	EXEC( @ScriptDeny )
	SET @Now = GETDATE() 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
	 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_DirectoryExists]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_DirectoryExists] ( @Path nvarchar(500) ) AS
BEGIN
	Declare @T TABLE (FileEx int,DirectoryEx int,ParentEX int)
	Insert INTO @T EXEC Master.dbo.xp_fileExist @Path
	Select DirectoryEx as Ret from @T
END
GO

/****** Object:  StoredProcedure [dbo].[USP_DirectoryExistsAll]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[USP_DirectoryExistsAll] 
					( 
					@Path1 nvarchar(500) , 
					@Path2 nvarchar(500) = NULL, 
					@Path3 nvarchar(500) = NULL, 
					@Path4 nvarchar(500) = NULL 
					) AS
BEGIN
	
	--Create table _temp (path1 nvarchar(500),path2 nvarchar(500),path3 nvarchar(500),path4 nvarchar(500) )
	SET NOCOUNT ON;
	--Insert into _temp  Values (@path1,@path2,@path3,@path4)
	Declare @T1 TABLE (FileEx int,DirectoryEx int,ParentEX int)
	Declare @Ret int
	Insert INTO @T1 EXEC Master.dbo.xp_fileExist @Path1
	IF @Path2 IS NOT NULL	Insert INTO @T1 EXEC Master.dbo.xp_fileExist @Path2
	IF @Path3 IS NOT NULL	Insert INTO @T1 EXEC Master.dbo.xp_fileExist @Path3
	IF @Path4 IS NOT NULL	Insert INTO @T1 EXEC Master.dbo.xp_fileExist @Path4

	IF EXISTS( Select distinct DirectoryEx  from @T1 Where DirectoryEx =0) SET @Ret =0 ELSE SET @Ret = 1
	RETURN @Ret

END	
GO

/****** Object:  StoredProcedure [dbo].[USP_Exists_Album_BySerial]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE proc [dbo].[USP_Exists_Album_BySerial]( @siAlbum int ) AS 
   SELECT  ISNULL(siAlbum,0) as siAlbum from AlbumTable  where siAlbum = @siAlbum



GO

/****** Object:  StoredProcedure [dbo].[USP_Exists_Files_ByID]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




Create Proc [dbo].[USP_Exists_Files_ByID]( @FileID int ) AS  
select   
    ISNULL(siFiles,0) as siFiles from FilesTable where FileID = @FileID



GO

/****** Object:  StoredProcedure [dbo].[USP_Exists_Files_BySerial]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE proc [dbo].[USP_Exists_Files_BySerial]( @siFiles int ) AS 
   select  ISNULL(siFiles,0) as siFiles from FilesTable  where sifiles = @siFiles








GO

/****** Object:  StoredProcedure [dbo].[USP_Exists_Service_By_siFiles]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Exists_Service_By_siFiles]( @siFiles  int, @ServiceType tinyint ) AS     
Begin     
  --  @ServiceType = 0 means CommonTarrif(0) Or Tebnegartarrif(1)
  --  @ServiceType = 2 means PrintAgain(2) Oe CDWriteAgain(2) 
  	
 IF EXISTS(  
   Select TOP 1 1  
   From ServiceTable ST    
   INNER JOIN CommonTariffTable CTT ON CTT.siCommonTariff = ST.siCommonTariff
   Where siFiles= @siFiles AND  CTT.Type = @ServiceType )  
  SELECT 1 AS HasService  
 ELSE  
  SELECT 0 AS HasService  
     
End; 
GO

/****** Object:  StoredProcedure [dbo].[USP_Get_FactorStatus]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Get_FactorStatus]( @siFiles int ) AS
BEGIN
	SELECT FactorStatus FROM WaitTable 
	WHERE siFiles= @siFiles
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_GetAlbumInfo]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_GetAlbumInfo](@siFiles int,@siAlbum int) AS    
 SELECT     
  siAlbum,ALT.siFiles,AlbumName,AlbumDate,SurgDate,ALT.Comment,AssurList, ISNULL(Remain,0) Remain    
 From AlbumTable ALT         
 inner join  FilesTable FT on FT.siFiles = ALT.siFiles    
 Where (ALT.siFiles = @siFiles) and (ALT.siAlbum = @siAlbum)


GO

/****** Object:  StoredProcedure [dbo].[USP_GetAlbumListByFiles]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_GetAlbumListByFiles](@siFiles int ) AS    
SELECT     
 siAlbum,ALT.siFiles,AlbumName,AlbumDate,SurgDate,ALT.Comment,AssurList,ISNULL(Remain,0) Remain  
From AlbumTable ALT         
inner join  FilesTable FT on FT.siFiles = ALT.siFiles    
Where ALT.siFiles = @siFiles    
order by siAlbum


GO

/****** Object:  StoredProcedure [dbo].[USP_GetCountDocument_ByAlbum]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







CREATE Proc [dbo].[USP_GetCountDocument_ByAlbum]( @siAlbum int ) AS    
 select Count(*) as CountRecord    

 from DocumentTable DT   
 inner join TypesTable TT on DT.TypeNumber = TT.Number   
 where siAlbum = @siAlbum    
  
  







GO

/****** Object:  StoredProcedure [dbo].[USP_GetDocument_ByAlbum]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_GetDocument_ByAlbum]( @siAlbum int ) AS  
select   
 siDocument,siAlbum,TypeNumber,Title,DocumentDate,Path,Document,SumCode,PathOrDoc,Comment,Type,ISNULL(siPage,0) as siPage,ISNULL(CheckValue,'0') as CheckValue
 from DocumentTable DT 
 inner join TypesTable TT on DT.TypeNumber = TT.Number 
 where siAlbum = @siAlbum


GO

/****** Object:  StoredProcedure [dbo].[USP_GetDocument_Info]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO











CREATE Proc [dbo].[USP_GetDocument_Info]( @siDocument int ) AS  
select   
 siDocument,siAlbum,TypeNumber,Title,DocumentDate,Path,
--Document,
SumCode,PathOrDoc,Comment,Type as TypeDoc,ISNULL(siPage,0) as siPage,ISNULL(CheckValue,'0') as CheckValue
 from DocumentTable DT
 inner join TypesTable TT on DT.TypeNumber = TT.Number   
 where siDocument = @siDocument


GO

/****** Object:  StoredProcedure [dbo].[USP_GetFile_thumb]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE proc  [dbo].[USP_GetFile_thumb]( @FileID int ) AS   
select    
  siFiles,FileID,thumb  
 from FilesTable  
 where  FileID = @FileID 




GO

/****** Object:  StoredProcedure [dbo].[USP_GetFolderPathForPatient]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_GetFolderPathForPatient](@siFiles int) AS
BEGIN
	SELECT 
		FT.FileID, FT.FName, FT.LName, FT.PathFolder,
		FT.Subject,
		DC.Job,
		FT.Bef_Aft,
		FT.Age,
		CONCAT(DC.LNAME,' ',DC.FNAme) as DoctorFullName,
		FT.PathFolder,
		'Path'= FT.PathFolder+'\'+
				Dc.FolderName+'\'+
				FT.LName+' '+
				FT.FName+' '+ 
				CAST(FT.FileId AS NVARCHAR(200)),
		'PathFinal'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Final',
		'PathEMail'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-EMail',
		'PathOriginal'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Original',
		'PathOther'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Others'
		 
	FROM FilesTable FT
	INNER JOIN  DoctorsTable DC  ON Ft.siDoctor = DC.siDoctors
	WHERE FT.siFiles = @siFiles
 
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_GetNewFileID]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_GetNewFileID]( @siBranch int  ) AS
BEGIN 
	Declare @NewID Int;
	Select @NewID = dbo.FN_GetNewFileID(@siBranch)
	SELECT @NewID as 'NewID' 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_GetSrg_ListByAlbum]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE Proc [dbo].[USP_GetSrg_ListByAlbum](@siAlbum int) AS   
Begin  
 Select AST.siSurgery,SurgeryName, sequent, Show ,'1' as Was   
        From AlbumSurgTable AST   
        inner join SurgeryTable ST On AST.siSurgery =ST.siSurgery  
 where siAlbum = @siAlbum   
 UNION      
 SELECT ST.siSurgery,SurgeryName, Sequent, Show ,'0' as Was  
 From SurgeryTable ST   
 WHERE Show = '1'   
  and ( siSurgery not in   
   ( Select siSurgery From AlbumSurgTable where siAlbum = @siAlbum ) )  
 Order By SurgeryName  
End  
  








GO

/****** Object:  StoredProcedure [dbo].[USP_Gozaresh]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Gozaresh]( @ReferDateFrom varchar(10),@ReferDateTo varchar(10) ) AS   
--Declare @ReferDateFrom varchar(10) =  '1397/05/25',@ReferDateTo varchar(10) =  '1397/07/27'  
SELECT     
 'Mode'=Case when ReferDate >= @ReferDateFrom and ReferDate <= @ReferDateTo  then 'R' else 'P' end ,  
 P_FileID, ReferDate,PaidDate,PatientName, DoctorName, Job, Subject, Bef_Aft,   
 HasPrivateTariffCost, SendType, WaitTime, WaitTimeOut, PayableFee, PaidAmount,   
 RemainAmount, Discount, Comment, RoundAmount  
INTO #TEMP  
FROM  VW_SELECT_All_Statistics   
WHERE ( ReferDate >= @ReferDateFrom and ReferDate <= @ReferDateTo )  
    OR( PaidDate >= @ReferDateFrom  and PaidDate  <= @ReferDateTo )  
order by 1  
 
Select   
 NULL as Report,  
 P_FileID, ReferDate, PatientName, DoctorName, Job, Subject, Bef_Aft,   
 HasPrivateTariffCost, SendType, WaitTime, WaitTimeOut, PayableFee, PaidAmount,   
 RemainAmount, Discount, Comment, RoundAmount,  
 NULL as SumPayableFee,NULL as SumPaidAmount,NULL as SumDiscount,NULL as SumRemainAmount,NULL as SumRoundAmount  
FROM #TEMP  
UNION ALL  
 
SELECT Report,NULL,NULL, NULL, NULL, NULL, NULL,NULL, NULL, NULL, NULL, NULL, NULL, NULL,NULL, NULL, NULL, NULL,  
SUM(SumPayableFee) SumPayableFee ,
SUM(SumPaidAmount) SumPaidAmount ,
SUM(SumDiscount) SumDiscount,
SUM(SumRemainAmount) SumRemainAmount,
SUM(SumRoundAmount)  SumRoundAmount 
FROM(
	SELECT   
	 'Report' as Report
	 ,SUM(PayableFee) as SumPayableFee ,SUM(PaidAmount) as SumPaidAmount  ,SUM(Discount) as SumDiscount  
	 ,SUM(RemainAmount) as SumRemainAmount ,SUM(RoundAmount) as SumRoundAmount  
	From #TEMP  
	WHERE mode = 'R'
	UNION ALL  
	SELECT 'Report',NULL ,SUM(RemainAmount),NULL ,NULL ,NULL
	From #TEMP  
	WHERE mode = 'P'
)B  
GROUP BY Report
Drop Table #TEMP  
  
--printf VW_SELECT_All_Statistics  
--  siFiles, P_FileID, PatientName, DoctorName, Job, FullName, ReferDate, SurgDate, WaitTime, WaitTimeOut, Subject, TotalNumber, Bef_Aft, HasPrivateTariffCost, PaidAfter, PreCost, SendType, H_PerDiscount, FixPrice, D_PerDiscount, SumAfter, AfterPrice, PayableFee, PaidAmount, RemainAmount, Discount, PaidDate, Comment, RoundAmount, Title, PerDiscount  
  
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Gozaresh_Amar]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_Gozaresh_Amar](@Today   varchar(10),	@Mode varchar(5), @IsSum tinyint) AS
BEGIN
	DECLARE 
	 @Zone1   varchar(10) ,@Zone2   varchar(10) ,@Zone3   varchar(10) ,@Zone4   varchar(10) ,@Zone5   varchar(10) ,@Zone6   varchar(10) ,  
	 @Zone7   varchar(10) ,@Zone8   varchar(10) ,@Zone9   varchar(10) ,@Zone10  varchar(10) ,@Zone11  varchar(10) ,@Zone12  varchar(10) ,  
	 @Zone13  varchar(10) ,@Zone14  varchar(10) ,@Zone15  varchar(10) ,@Zone16  varchar(10) ,@Zone17  varchar(10) ,@Zone18  varchar(10) ,  
	 @Zone19  varchar(10) ,@Zone20  varchar(20) ,@Zone21  varchar(10) ,@Zone22  varchar(10) ,@Zone23  varchar(10) ,@Zone24  varchar(10)
 
	;WITH CTE AS
	(
		Select 
			Shamsi, ROW_NUMBER() OVER (Order by ID desc) as RowNO 
		from TblDate
		where Shamsi <= @Today and ( (DayInMonth = 1 and @Mode='M') or ( DayInWeek=1 and @Mode='W') )
	)
	SELECT 
		@Zone1=G1,
		@Zone2=G2,
		@Zone3=G3,
		@Zone4=G4,
		@Zone5=G5,
		@Zone6=G6,
		@Zone7=G7,
		@Zone8=G8,
		@Zone9=G9,
		@Zone10=G10,
		@Zone11=G11,
		@Zone12=G12,
		@Zone13=G13,
		@Zone14=G14,
		@Zone15=G15,
		@Zone16=G16,
		@Zone17=G17,
		@Zone18=G18,
		@Zone19=G19,
		@Zone20=G20,
		@Zone21=G21,
		@Zone22=G22,
		@Zone23=G23,
		@Zone24=G24
	FROM
	(
	SELECT 
	 Shamsi, CONCAT('G',RowNO) as RowNO
	from CTE 
	WHERE rowNO <= 24
	) PVT 
 
	PIVOT(
		MAX(Shamsi) 
		FOR RowNO IN (
			G1,G2,G3,G4,G5,G6,G7,G8,G9,G10,G11,G12,G13,
			G14,G15,G16,G17,G18,G19,G20,G21,G22,G23,G24
			)
	) AS pivot_table;
 
	Create table #TEMP 
	(siDoctor Int, DoctorName varchar(100), Job varchar(50),siHospital int,FullName varchar(100),IsTebDoc tinyint,
	Zone1 int,Zone2 int,Zone3 int,Zone4 int,Zone5 int,Zone6 int,Zone7 int,Zone8 int,Zone9 int,Zone10 int,
	Zone11 int,Zone12 int,Zone13 int,Zone14 int,Zone15 int,Zone16 int,Zone17 int,Zone18 int,Zone19 int,
	Zone20 int,Zone21 int,Zone22 int,Zone23 int,Zone24 int)
	INSERT INTO #TEMP   
	EXEC [dbo].[USP_Select_Statistic_PIVOT]  
	 @Today  ,  
	 @Zone1   ,@Zone2   ,@Zone3   ,@Zone4   ,@Zone5   ,@Zone6   ,  
	 @Zone7   ,@Zone8   ,@Zone9   ,@Zone10  ,@Zone11  ,@Zone12  ,  
	 @Zone13  ,@Zone14  ,@Zone15  ,@Zone16  ,@Zone17  ,@Zone18  ,  
	 @Zone19  ,@Zone20  ,@Zone21  ,@Zone22  ,@Zone23  ,@Zone24  ,
	 NULL 

	IF @IsSum =1 
		Select 
		siDoctor,DoctorName,Job,IsTebDoc,NULL as siHospital,NULL as FullName,
		SUM(Zone1) as Zone1,
		SUM(Zone2) as Zone2,
		SUM(Zone3) as Zone3,
		SUM(Zone4) as Zone4,
		SUM(Zone5) as Zone5,
		SUM(Zone6) as Zone6,
		SUM(Zone7) as Zone7,
		SUM(Zone8) as Zone8,
		SUM(Zone9) as Zone9,
		SUM(Zone10) as Zone10,
		SUM(Zone11) as Zone11,
		SUM(Zone12) as Zone12,
		SUM(Zone13) as Zone13,
		SUM(Zone14) as Zone14,
		SUM(Zone15) as Zone15,
		SUM(Zone16) as Zone16,
		SUM(Zone17) as Zone17,
		SUM(Zone18) as Zone18,
		SUM(Zone19) as Zone19,
		SUM(Zone20) as Zone20,
		SUM(Zone21) as Zone21,
		SUM(Zone22) as Zone22,
		SUM(Zone23) as Zone23,
		SUM(Zone24) as Zone24
	from #TEMP 
	Group by all siDoctor,DoctorName,Job,IsTebDoc 
	Order by DoctorName
	ELSE
	Select 
	siDoctor,DoctorName,Job,IsTebDoc,siHospital,FullName,
	Zone1,
	Zone2,
	Zone3,
	Zone4,
	Zone5,
	Zone6,
	Zone7,
	Zone8,
	Zone9,
	 Zone10,
	 Zone11,
	 Zone12,
	 Zone13,
	 Zone14,
	 Zone15,
	 Zone16,
	 Zone17,
	 Zone18,
	 Zone19,
	 Zone20,
	 Zone21,
	 Zone22,
	 Zone23,
	 Zone24
	from #TEMP 
	Order by DoctorName
 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_AccountTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Insert_AccountTable](            
 @siFiles int,@siDiscount int,@PerDiscount int, @Discount int, @FactorDate varchar(10),@DiscountTitle varchar(500), @TotalPrice int,
 @PayableFee int, @PaidAmount int,@RemainAmount int,@RoundAmount int,@PaidDate varchar(10) ,@Type tinyint, @Comment varchar(500),          
 @T_F int, @T_B int, @T_A int, @T_O int,    
 @Used_Location  int,@Use_Bef_Aft int,@Used_PreCost int,@Used_PaidAfter int,@Used_SendType int,    
 @Used_BefTariff varchar(50),@Used_BefAmount varchar(50),@Used_AftTariff varchar(50),@Used_AftAmount varchar(50),@IsExtra tinyint ) AS             
Begin             
 Insert into  AccountTable(
  siFiles,siDiscount,PerDiscount,Discount,FactorDate,DiscountTitle,TotalPrice,PayableFee,
  PaidAmount, RemainAmount,RoundAmount,PaidDate,Type,Comment,T_F,T_B,T_A,T_O,Used_Location,
  Use_Bef_Aft, Used_PreCost,Used_PaidAfter,Used_SendType,Used_BefTariff,Used_BefAmount,
  Used_AftTariff,Used_AftAmount,IsExtra   
   )            
 values(    
  @siFiles,@siDiscount,@PerDiscount,@Discount,@FactorDate,@DiscountTitle,@TotalPrice,@PayableFee,
  @PaidAmount,@RemainAmount, @RoundAmount,@PaidDate,@Type,@Comment,@T_F,@T_B,@T_A,@T_O,@Used_Location,
  @Use_Bef_Aft,@Used_PreCost,@Used_PaidAfter,@Used_SendType,@Used_BefTariff,@Used_BefAmount,
  @Used_AftTariff,@Used_AftAmount,@IsExtra   
  )            
 Return SCOPE_IDENTITY()             
End 
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_AlbumSurgTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_AlbumSurgTable](@siAlbum int,@siSurgery int) AS 
Begin 
	Declare @siFiles int;
	Insert into AlbumSurgTable(siAlbum,siSurgery )values(@siAlbum,@siSurgery)
	Return SCOPE_IDENTITY() 

End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_AlbumTable]    Script Date: 7/26/2020 2:53:38 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_AlbumTable](  
 @siFiles int,@AlbumName varchar(50),@AlbumDate varchar(10), @SurgDate varchar(10),
 @Comment varchar(200), @AssurList varchar(200), @Remain int ) AS   
Begin   
 Insert into AlbumTable(siFiles,AlbumName,AlbumDate,SurgDate,Comment,AssurList,Remain )  
 values(@siFiles,@AlbumName,@AlbumDate,@SurgDate,@Comment,@AssurList,@Remain)  
 Return SCOPE_IDENTITY() 
End;  
  
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_BoxInfoTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Insert_BoxInfoTable](
	@siPage int,@Grp int,@Type int,@Xmargin int,@Ymargin int,@Status int) AS 
Begin 
 Insert into BoxInfoTable(siPage,Grp,Type,Xmargin,Ymargin,Status )
	values(@siPage,@Grp,@Type,@Xmargin,@Ymargin,@Status)
 Return SCOPE_IDENTITY() 
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_CommonTariffTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


Create Proc [dbo].[USP_Insert_CommonTariffTable](
	@TariffName varchar(50),@Price int,@Type tinyint,@IsAfter tinyint,@Countable tinyint,@Comment varchar(200)) AS 
Begin 
 Insert into CommonTariffTable(TariffName,Price,Type,IsAfter,Countable,Comment )
	values(@TariffName,@Price,@Type,@IsAfter,@Countable,@Comment)
 Return SCOPE_IDENTITY() 
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_DoctorsTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


Create Proc [dbo].[USP_Insert_DoctorsTable](
	@FileID int,@FName varchar(15),@LName varchar(25),@Job varchar(50),@Address1 varchar(200),@Address2 varchar(200),@Address3 varchar(200),@Address4 varchar(200),@Comment varchar(4000),@Tag1 int,@Tag2 int,@Tag3 int,@Tag4 int) AS 
Begin 
 Insert into DoctorsTable(FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4 )
	values(@FileID,@FName,@LName,@Job,@Address1,@Address2,@Address3,@Address4,@Comment,@Tag1,@Tag2,@Tag3,@Tag4)
 Return SCOPE_IDENTITY() 
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_DocumentTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









CREATE Proc [dbo].[USP_Insert_DocumentTable](
	@siAlbum int,@TypeNumber int,@Title varchar(50),@DocumentDate varchar(10),@Path varchar(200),@SumCode int, @PathOrDoc int,@Comment varchar(200) ) AS 
Begin 
 Insert into DocumentTable(siAlbum,TypeNumber,Title,DocumentDate,Path,SumCode,PathOrDoc,Comment )
	values(@siAlbum,@TypeNumber,@Title,@DocumentDate,@Path,@SumCode,@PathOrDoc,@Comment)
 Return SCOPE_IDENTITY() 
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_DocumentTable_Check]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Insert_DocumentTable_Check](
	@siAlbum int,@Title varchar(50),@Comment varchar(200),@siPage int, @CheckValue varchar(100) ) AS 
Begin 
 Insert into DocumentTable(siAlbum,TypeNumber,Title,DocumentDate,Path,SumCode,PathOrDoc,Comment,siPage,CheckValue )
	values(@siAlbum,9,@Title,NULL,NULL,0,1,@Comment,@siPage, @CheckValue)
 Return SCOPE_IDENTITY() 
End;




GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_ExtraServiceTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_ExtraServiceTable](        
	  @siAccount int, @siCommonTariff int, @FactorDate varchar(10),   
	@Number int, @Type int, @UsedTariffName varchar(10), @UsedPrice int   
	) AS         
Begin         
	 Insert into ExtraServiceTable(siAccount, siCommonTariff, FactorDate, Number, Type, UsedTariffName, UsedPrice )        
	 values(@siAccount, @siCommonTariff, @FactorDate, @Number, @Type, @UsedTariffName, @UsedPrice)        
	 Return SCOPE_IDENTITY()         
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_FileReceiptTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_FileReceiptTable] 
	(@siFiles int,@BackColor tinyint,@LifeSize bit, @GridLine bit, @TopCategory varchar(8000), @SubCategory1 varchar(8000), @SubCategory2 varchar(8000), @Comment1 nvarchar(4000), @Comment2 nvarchar(4000) ) AS
BEGIN
	DECLARE @siSession int;
	Select @siSession= siSession from SessionTable where SPID = @@SPID
	
	Insert into FileReceiptTable(siFiles,BackColor,LifeSize,GridLine,TopCategory, SubCategory1, SubCategory2, Comment1, Comment2, siSession )  
	values(@siFiles,@BackColor,@LifeSize,@GridLine, NULLIF(LTRIM(RTRIM(@TopCategory)),''), NULLIF(LTRIM(RTRIM(@SubCategory1)),''), NULLIF(LTRIM(RTRIM(@SubCategory2)),''), @Comment1, @Comment2, @siSession)  
	Return SCOPE_IDENTITY();   
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_FilesTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_FilesTable](        
 @FileID int,@FName varchar(15),@LName varchar(25),@Phone1 varchar(20),@Phone2 varchar(20),@RefPlace varchar(100),@PaidAfter int,@BirthYear varchar(4),@ReferDate varchar(10),      
 @Subject varchar(200),@Comment varchar(4000),@Address  varchar(200),@Age int ,@SendType int ,@DoctorName varchar(50),@Job varchar(50), @siDoctor int,    
 @RefFileID int,@siHospital int,@Bef_Aft tinyint,@Sex tinyint, @PathFolder nvarchar(500), @siBranch int, @Is3D tinyint ) AS         
Begin         
	Insert into FilesTable(FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,Comment,Address,Age,SendType,DoctorName,Job,siDoctor,RefFileID,siHospital,Bef_Aft,Sex,PathFolder, siBranch, Is3D )        
	values(@FileID,@FName,@LName,@Phone1,@Phone2,@RefPlace,@PaidAfter ,@BirthYear,@ReferDate,@Subject,@Comment,@Address,@Age ,@SendType ,@DoctorName,@Job,@siDoctor,@RefFileID,@siHospital,@Bef_Aft,@Sex,@PathFolder, @siBranch, @Is3D)        
	Return SCOPE_IDENTITY()         
End;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_ListOfSurgeryByFile_String]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Insert_ListOfSurgeryByFile_String]( @siFiles int ) AS    
BEGIN    
  SET NOCOUNT ON    
Declare @I int , @CNT int, @L int  
Declare @T varchar(1000),@Temp varchar(50)     
SELECT   DISTINCT   
   ST.SurgeryName   INTO #TEMP1  
FROM    FilesTable  FT     
INNER JOIN  AlbumTable ALT ON FT.siFiles = ALT.siFiles     
INNER JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum     
INNER JOIN  SurgeryTable ST ON AST.siSurgery = ST.siSurgery    
where FT.siFiles = @siFiles    
order by ST.SurgeryName desc    
  
SELECT   Distinct    
  identity(int,1,1) Row,SurgeryName   INTO #TEMP  
FROM  #TEMP1    
  
SET @CNT = @@ROWCOUNT    
 
  IF @CNT =0   
  BEGIN
    UPDATE FilesTable 
	SET Subject = NULL
    WHERE siFiles = @siFiles 
    RETURN
  END   

  SET @I = 1    
  SET @T=''    
  
    WHILE @I <= @CNT    
    BEGIN    
      SELECT @Temp = SurgeryName FROM #TEMP WHERE ROW = @I    
      SET @T = @Temp + ', ' + @T     
      SET @I = @I +1    
    END    
  
    SET @L = Len(@T)    
    SET @T = Left( @T, @L-1 )

    UPDATE FilesTable 
	SET Subject = @T
    WHERE siFiles = @siFiles 
 
  
drop Table #Temp    
drop Table #Temp1    
    
  SET NOCOUNT OFF    
    
END    
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_NewLabPatient_Into_TebnegarPatient]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Insert_NewLabPatient_Into_TebnegarPatient] AS
BEGIN   	
-- compatible with parsipol 0 
	UPDATE P
		SET Status = -1
	FROM NovinTebnegarPatients P
	INNER JOIN NovinAcceptation AC  ON P.fCode = AC.fCode 
	WHERE ReAccept = 1 
 
	INSERT INTO NovinTebnegarPatients 
	(FileID, fcode, FName, LName, Phone1, Mobile, SendType, SendStatus, BirthYear,  MiladiDate, ReferDate, DoctorName, 
	 siDoctor,AutoStatus,MedicalID, Sex, SexTitle, Status,RegisterDate, TelegramStatus)
	SELECT   
			AC.fcode as FileId, 
			AC.fcode, 
			AC.fFirstName as FName, 
			AC.fLastName as LName,
			NULL as Phone1,
			AC.fMobile as Mobile,
			'SendType' = CASE fEmergency WHEN 1 THEN 0 WHEN 0 THEN 1  END,   
			'SendStatus' = CASE fEmergency WHEN 1 THEN N'اورژانس' WHEN 0 THEN N'عادي' END,
			LEFT(AC.fBirthDate,4) BirthYear, 
			CAST(fDateTime as DATE ) as MiladiDate, 
			fAcceptionDate as ReferDate,
			CONCAT(TD.ffirstName collate SQL_Latin1_General_CP1256_CI_AS ,' ',TD.fLastName collate SQL_Latin1_General_CP1256_CI_AS) as DoctorName,
			DM.siDoctors,
			CASE WHEN DM.siDoctors IS NULL THEN NULL ELSE 1 END as AutoStatus,
			LTRIM(RTRIM(TD.fCodeNezamPezeshki)) as MedicalID,
			fSex as Sex,
			'SexTitle' = CASE fSex WHEN 0 THEN N'زن' WHEN 1 THEN N'مرد' END, 			
			CASE 
				WHEN fCancellation=1 THEN  2 -- canceled
				WHEN fCancellation=0 and fPutAnswer=1 THEN  3  -- putAnswered
				ELSE 1 -- not proccessed
			END  as Status,
			fAcceptionDateTime as RegisterDate,
			0 as TelegramStatus
	FROM NovinAcceptation AC 
	INNER JOIN NovinDoctor TD ON AC.fCodeDoctor = TD.fCode
	LEFT  HASH JOIN VW_SYS_DoctorMatchList DM ON DM.fCodeDoctor = TD.fCode
	WHERE   ReAccept <> 1 and
			CAST(fAcceptionDateTime as DATE) = CAST( Getdate() as DATE) AND
			fCancellation = 0 AND 
			AC.fCode NOT IN ( SELECT ISNULL(FCode,0) From NovinTebnegarPatients)
 
	---------------------------------------------------------------------------------------------
	UPDATE 	TP
	SET 
		Status = 
				CASE 
					WHEN fCancellation=1 THEN  2 -- canceled
					WHEN fCancellation=0 and fPutAnswer=1 THEN  3  -- putAnswered
				ELSE 1 -- not proccessed
				END
		,AnswerDate = 
					CASE 
						WHEN Status = 3 and AnswerDate IS NULL THEN GetDate() -- The patients from teb that fills by NOVIN program
						WHEN Status <>3 and fPutAnswer=1   THEN GetDate() -- The patients from lab that does not fill by NOVIN program
						ELSE AnswerDate
					END
	FROM	NovinTebnegarPatients TP
	INNER JOIN NovinAcceptation AC  ON TP.fCode = AC.fCode
	WHERE 	TP.Status >0 and 
		(DATEDIFF(DAY, RegisterDate, GETDATE() )) <= ( Select TelegramDays From ConfigTable)
 
		
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_PageTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




Create Proc [dbo].[USP_Insert_PageTable](
	@CheckCount int,@TitlePage varchar(200),@PagePhoto image) AS 
Begin 
 Insert into PageTable(CheckCount,TitlePage,PagePhoto )
	values(@CheckCount,@TitlePage,@PagePhoto)
 Return SCOPE_IDENTITY() 
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_ServiceTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Insert_ServiceTable](    
 @siFiles int,@siWait int,@siCommonTariff int,@Number int,@Type tinyint,
 @UsedTariffName varchar(50), @UsedPrice int) AS     
Begin     
 Insert into ServiceTable(siFiles,siWait,siCommonTariff,Number ,Type, UsedTariffName,UsedPrice )    
 values(@siFiles,@siWait,@siCommonTariff,@Number,@Type,@UsedTariffName,@UsedPrice )    
 Return SCOPE_IDENTITY()     
End;  
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_SessionTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Insert_SessionTable]( @siUser int, @UserName nvarchar(50),@SPID int, @Comment nvarchar(500)) AS
BEGIN
	DELETE SessionTable WHERE SPID = @SPID;
	INSERT INTO SessionTable(siUser, UserName, SPID, LoginDate, Machine)
	VALUES( @siUser , @UserName ,@SPID , GETDATE(),@Comment)

	Return SCOPE_IDENTITY(); 
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_SurgeryTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_Insert_SurgeryTable](
	@SurgeryName varchar(50),@LatinName varchar(50),@Sequent int,@Show varchar(1)='1') AS 
Begin 
 Insert into SurgeryTable(SurgeryName,LatinName,Sequent,Show )
	values(@SurgeryName,@LatinName,@Sequent,@Show)
 Return SCOPE_IDENTITY() 
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_TypesTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









CREATE Proc [dbo].[USP_Insert_TypesTable](
	@Number int,@Type varchar(15)) AS 
Begin 
 Insert into TypesTable(Number,Type )
	values(@Number,@Type)
 Return SCOPE_IDENTITY() 
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Insert_WaitTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Insert_WaitTable](
	@siFiles int,@WaitDate varchar(10),@WaitTime varchar(5),@WaitTimeOut varchar(5),@SurgStatus tinyint,@Status tinyint,@Comment varchar(500)) AS 
Begin 
 Insert into WaitTable(siFiles,WaitDate,WaitTime,WaitTimeOut,SurgStatus,Status,Comment )
	values(@siFiles,@WaitDate,@WaitTime,@WaitTimeOut,@SurgStatus,@Status,@Comment)
 Return SCOPE_IDENTITY() 
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_IsFactorIssued]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_IsFactorIssued]( @siFiles int) AS           
BEGIN           
	
	SELECT 	siAccount 	FROM AccountTable WHERE siFiles= @siFiles 
	
END      
GO

/****** Object:  StoredProcedure [dbo].[USP_MoveDocument]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







create proc [dbo].[USP_MoveDocument](@siDocument int,@siNewAlbum int ) AS
begin
  Update   DocumentTable
     SET siAlbum = @siNewAlbum  
  where siDocument = @siDocument
end






GO

/****** Object:  StoredProcedure [dbo].[USP_MoveFolder]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE	PROCEDURE [dbo].[USP_MoveFolder]( @OldFolderName nvarchar(1000), @NewFolderName nvarchar(1000), @LoginName varchar(20)) AS
BEGIN
	
	DECLARE @Script nvarchar(1000)=''
	
	EXEC USP_CloseOpenedFiles  @NewFolderName, @OldFolderName
 
	DECLARE @Ret int,@TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	SET @Script = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /xmove "'+@OldFolderName+ '" "'+@NewFolderName+'"''' 

FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END	 

	EXEC ( @Script )
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
	
END	
GO

/****** Object:  StoredProcedure [dbo].[USP_NOVIN_Select_Patients]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_NOVIN_Select_Patients] ( @FileID int ) AS
	SELECT 
	 FileID, FName, LName, Phone1, RefPlace, SendType,
	 'SendStatus' = CASE SendType           
		 WHEN 0 THEN 'اورژانس'           
		 WHEN 1 THEN 'عادي'           
		END ,  BirthYear, ReferDate, DoctorName, null as fCodeNezamPezeshki , Sex
	FROM FilesTable
	WHERE (FileID =@FileID)
	ORDER BY ReferDate DESC 
GO

/****** Object:  StoredProcedure [dbo].[USP_Remove_Permission]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Remove_Permission]( @DeleteAll bit ) AS
BEGIN
	DECLARE @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
 
	DECLARE   @siPermission INT=0, @ScriptDeny nvarchar(1000)='', @ScriptDeny2 nvarchar(1000)='', @MSG nvarchar(max)='';
	
	DECLARE @Deleted Table (
							siPermission int ,
							LoginName varchar(20) ,
							Status char(1),
							siFile int ,
							ScriptGrant nvarchar(1000) ,
							ScriptDeny nvarchar(1000),
							ActionTime datetime ,
							ErrorMessage nvarchar(max)
							) 
 
	;WITH CTE AS
	(
		Select 
			siPermission,LoginName,Status,siFile,ScriptGrant,ScriptDeny,ActionTime,ErrorMessage ,
			ROW_NUMBER() OVER( Partition by LoginName, siFile Order by ActionTime desc) AS RW
		from  PermissionTable  
	)
 
	DELETE CTE 
	OUTPUT deleted.siPermission,deleted.LoginName,deleted.Status,deleted.siFile,deleted.ScriptGrant,deleted.ScriptDeny,deleted.ActionTime,deleted.ErrorMessage
	INTO @Deleted 
	WHERE RW <> 1;
	
	INSERT INTO PermissionTable_Log(siPermission,LoginName,Status,siFile,ScriptGrant,ScriptDeny,ActionTime,ErrorMessage)
	SELECT siPermission,LoginName,Status,siFile,ScriptGrant,ScriptDeny,ActionTime,ErrorMessage
	FROM  @Deleted 
 	WHERE siFile <>0
 
	DECLARE permission_cursor CURSOR FOR  
	WITH CTE AS
	(
		SELECT 
			siPermission,ScriptDeny,
			N'xp_cmdshell N''ICACLS "'+
			F.PathFolder +'\'+ T.FolderName+'\'+LTrim(RTrim(F.LName))+' '+LTrim(RTrim( F.FName ))+' '+LTrim(RTrim( F.FileID ) ) +
			'" /remove '+LoginName+' /T ''' as ScriptDeny2 
			,ROW_NUMBER()OVER( Partition by LoginName Order by ActionTime desc) as RW
		FROM 
		(	
			SELECT 
				siPermission,LoginName,siFile,ScriptGrant,ScriptDeny,ActionTime, DATEDIFF(Second, ActionTime,getdate()) PassedTime 
			FROM PermissionTable 
			WHERE DATEDIFF(Second, ActionTime,getdate()) > 30
		)A
		LEFT JOIN FilesTable F with (nolock) ON A.siFile = F.siFiles 
		LEFT JOIN  DoctorsTable T ON F.siDoctor = T.siDoctors
 
	)
	SELECT 
		siPermission,ScriptDeny,ScriptDeny2
	FROM CTE  
	WHERE RW <>1 OR @DeleteAll = 1
 
	OPEN permission_cursor  
		FETCH NEXT FROM permission_cursor INTO @siPermission ,@ScriptDeny ,@ScriptDeny2 
		WHILE @@FETCH_STATUS = 0  
		BEGIN  
			BEGIN TRY
			EXEC( @ScriptDeny ) 
			EXEC( @ScriptDeny2) 
			DELETE PermissionTable WHERE siPermission = @siPermission 
			END TRY
			BEGIN CATCH
			SET @MSG =ERROR_MESSAGE();
			UPDATE PermissionTable SET ErrorMessage= @MSG WHERE siPermission = @siPermission
			END CATCH
			FETCH NEXT FROM permission_cursor INTO @siPermission , @ScriptDeny ,@ScriptDeny2
		END  
  
		CLOSE permission_cursor  
		DEALLOCATE permission_cursor  
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
  
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_RemoveAllPermissionFolder]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_RemoveAllPermissionFolder] ( @siFiles int, @LoginName varchar(20), @OldPath nvarchar(1000) ) AS
BEGIN
   
	IF @LoginName in('quality','tebnegar') RETURN 0
		
	DECLARE @Ret int,@TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I',NULL,@siFiles
 
	DECLARE @Path nvarchar(1000)=''
	SELECT		
		@Path=F.PathFolder +'\'+T.FolderName+'\'+LTrim(RTrim(F.LName))+' '+LTrim(RTrim( F.FName ))+' '+LTrim(RTrim( F.FileID ) ) 
	FROM FilesTable F 
	INNER JOIN  DoctorsTable T ON F.siDoctor = T.siDoctors 
	WHERE F.siFiles = @siFiles
 
 
	DECLARE  @Deny  nvarchar(4000),@Deny2 nvarchar(4000);
 
	SELECT	@LoginName = LoginName	FROM LoginGroup	WHERE IsGroup  =1 
 
	SET @Deny  = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /deny "'+@Path   + '" '+@LoginName+'''' 
	SET @Deny2 = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /deny "'+@OldPath+ '" '+@LoginName+'''' 
	
FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC(@Deny)
	IF LTRIM(RTRIM(@OldPath)) <>'' 	EXEC(@Deny2)
	
 
	INSERT INTO PermissionLogTable(siFile) VALUES(@siFiles)
	 
	Delete PermissionTable Where siFile = @siFiles
 
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
	 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_RemoveGrantForClose]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[USP_RemoveGrantForClose] ( @siFiles int, @LoginName varchar(20) ) AS
BEGIN
	if @LoginName in('quality','tebnegar') Return
	UPDATE PermissionTable SET Status = 'R' WHERE LoginName = @LoginName
END
GO

/****** Object:  StoredProcedure [dbo].[USP_RenameFolder]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_RenameFolder] ( @OldFolderName nvarchar(1000), @NewFolderName nvarchar(1000), @LoginName varchar(20), @IsRoot tinyint) AS
BEGIN
 
	DECLARE @Script nvarchar(1000)='', @NewName nvarchar(1000)=''
	SET @NewName= LTRIM(RTRIM(Right(@NewFolderName,CharIndex('\',Reverse(@NewFolderName) )-1 )))
 
	IF @NewName='' Return
	DECLARE @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
	
	EXEC USP_CloseOpenedFiles @OldFolderName, @NewFolderName

	SET @Script = N'xp_cmdshell N''Ren "'+@OldFolderName+ '" "'+@NewName+'" ''' 
	EXEC ( @Script )
	SET @Now = GETDATE() 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U',@OldFolderName
 
END	
  
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_RenameFolder_Pre]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_RenameFolder_Pre] ( @OldFolderName nvarchar(1000), @NewFolderName nvarchar(1000), @LoginName varchar(20), @IsRoot tinyint) AS
BEGIN
 
	DECLARE @Script nvarchar(1000)='', @NewName nvarchar(1000)=''
	SET @NewName= LTRIM(RTRIM(Right(@NewFolderName,CharIndex('\',Reverse(@NewFolderName) )-1 )))
 
	IF @NewName='' Return
	DECLARE @TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I'
	--Must be Changed
	SET @Script = N'xp_cmdshell N''Ren "'+@OldFolderName+ '" "'+@NewName+'" ''' 
	EXEC ( @Script )
	SET @Now = GETDATE() 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U'
 
END	
 
GO

/****** Object:  StoredProcedure [dbo].[USP_RenameSpecifiedDirectory]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_RenameSpecifiedDirectory](@src [nvarchar](1000), @dest [nvarchar](1000)) AS
BEGIN
	Select dbo.RenameSpecifiedDirectory(@src, @dest) as Ret
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Repair_BadAges]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



Create Proc [dbo].[USP_Repair_BadAges] AS
 update FilesTable
  Set Age = cast(Left(ReferDate,4) as int) - cast( BirthYear as int)



GO

/****** Object:  StoredProcedure [dbo].[USP_Repair_BadDates]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO







CREATE PROC [dbo].[USP_Repair_BadDates] AS      
BEGIN      
 DECLARE @L INT ,@Sal VARCHAR(4) ,@Mah VARCHAR(2) , @Roz VARCHAR(2)  
  
 DECLARE @siFiles INT , @MyDate VARCHAR(10)  
 DECLARE Files_cursor CURSOR FOR  
         SELECT siFiles,ReferDate FROM FilesTable WHERE LEN(ReferDate) BETWEEN 1 AND 9  
  
 OPEN Files_cursor  
 FETCH NEXT FROM Files_cursor INTO @siFiles , @MyDate  
 WHILE @@FETCH_STATUS = 0  
 BEGIN  
  
  SET @L = 0  
  SET @L = PATINDEX('%/%', @MyDate )  
  IF  5 -@L = 2  SET @MyDate = '13' +@MyDate   ELSE IF 5 -@L =1 SET @MyDate = '1' +@MyDate    
  SET @L = Len(@MyDate)     
  SET @SAL = Left( @MyDate, 4 )  SET @MyDate =  Right( @MyDate, @L -5 )  
    
  SET @L = PATINDEX('%/%', @MyDate)  
  IF 3 -@l = 1  SET @MyDate = '0' +@MyDate     
  SET @L = Len(@MyDate)  
  SET @Mah = Left( @MyDate, 2 )  SET @MyDate =  Right( @MyDate, @L -3)  
    
  IF LEN(@MyDate) = 1 SET @MyDate = '0'+@MyDate     
  SET @Roz = @MyDate  
  SET @MyDate = @SAL +'/'+@Mah+'/'+@Roz  
  
           UPDATE FilesTable SET ReferDate = @MyDate WHERE siFiles = @siFiles    
    FETCH NEXT FROM Files_cursor INTO @siFiles , @MyDate  
 END  
  
 CLOSE Files_cursor  
 DEALLOCATE Files_cursor  
  
END      
  




GO

/****** Object:  StoredProcedure [dbo].[USP_Reset_LinkedDoctor]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Reset_LinkedDoctor] ( @fCode numeric(12, 0) ) as
BEGIN
	DECLARE @fDoctorName nvarchar(50)='', @fCodeNezamPezeshki nvarchar(50)='', @Status int; 
 
	SELECT @fDoctorName=TD.FName, @fCodeNezamPezeshki=fCodeNezamPezeshki, 
	@Status=
		Case 
			when fCancellation =1 then  2 
			when fPutAnswer =1	  then  3
			else 1 
		end
	FROM NovinAcceptation A
	INNER JOIN  NovinDoctor TD ON TD.fCode = A.fCodeDoctor  
	WHERE A.fCode= @fCode
 
	UPDATE  NovinTebnegarPatients 
	SET	
		DoctorName = @fDoctorName,
		MedicalID = @fCodeNezamPezeshki,
		AutoStatus = NULL,
		siDoctor = NULL,
		SentSMS = NULL,
		SentSMSTime=NULL,
		SendDate=NULL,
		TryCount =NULL,
		TelegMessageId=NULL,
		TelegramStatus= NULL
	WHERE fCode =@fCode
 
END;
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_RPT_Select_Today_AccountList]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_RPT_Select_Today_AccountList](@Date as varchar(10), @siBranch int) as
BEGIN
	SELECT 
		 RW= ROW_NUMBER() OVER ( ORDER BY (SELECT NULL)),
		'PatientName'=ISNULL(FT.LName,'')+' '+ ISNULL(FT.FName,''), 
		FT.RefPlace,
		FT.Subject, 
		BR.BranchName, 
		FT.DoctorName,
		'TotalPrice'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'')  IS NOT NULL) and (PaidDate <> FactorDate ) then 	NULL
						else ACT.TotalPrice
					end,
		'PaidAmount'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NOT NULL) and (PaidDate <> FactorDate ) then 	NULL
						else ACT.PaidAmount
					end,
		'RoundAmount'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NOT NULL) and (PaidDate <> FactorDate ) then 	NULL
						else ACT.RoundAmount
					end,
		'DiscountTitle'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NOT NULL) and (PaidDate <> FactorDate ) then 	NULL
						else ACT.DiscountTitle
					end,
		'RemainAmount'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NOT NULL) and (PaidDate <> FactorDate ) then 	NULL
						else ACT.RemainAmount
					end,
		'PaidRemain'=
					Case 
						When (NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NOT NULL) and (PaidDate = FactorDate ) then 	ACT.RemainAmount
						When NULLIF(LTRIM(RTRIM(PaidDate)),'') IS NULL then 	0
						else ACT.RemainAmount
					end,
		ACT.Comment
	FROM  AccountTable ACT
	INNER JOIN FilesTable FT ON ACT.siFiles = FT.siFiles
	INNER JOIN BranchTable BR ON FT.siBranch = BR.siBranch
	WHERE ((FactorDate = @Date) OR (PaidDate = @Date)) AND ( @siBranch =0 OR FT.siBranch = @siBranch ) 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_RPT_Select_Today_WaitList]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_RPT_Select_Today_WaitList](@WaitDate as varchar(10), @siBranch int) as
BEGIN
	SELECT 
		 RW= ROW_NUMBER() OVER ( order by  WaitTimeOut),
		'PatientName'=ISNULL(FT.LName,'')+' '+ ISNULL(FT.FName,''), 
		 FT.RefPlace, 
		 FT.DoctorName, 
 		 FT.Subject, 
		 BR.BranchName, 
		 FT.Job, 
		 'Bef_Aft'=  Case when FT.Bef_Aft= 0 then 'Before' else 'After' end,   
		 'SendType'= Case when FT.SendType= 0 then N'اورژانس' else N'عادی' end ,
		 ALT.SurgDate

	FROM WaitTable WT 
	inner join FilesTable FT ON WT.siFiles = FT.siFiles
	INNER JOIN BranchTable BR ON FT.siBranch = BR.siBranch
	inner join AlbumTable ALT ON FT.siFiles = ALT.siFiles
	WHERE status >= 16 and  WaitDate = @WaitDate and ( @siBranch =0 OR FT.siBranch = @siBranch ) 
	ORDER BY wt.WaitTimeOut
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_3DWaitTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_Select_3DWaitTable](@siFiles int =0 ) AS 
BEGIN
	SELECT 
		siWait3D, siFiles, Status, DeliveryTime, TakePhoto, DenseCloudTime, TebPaidTime, Object3DTime, ShotCount, DenseCount, ObjectCount, Comment, Comment2, Comment3
	FROM Wait3DTable
	WHERE @siFiles= 0 OR siFiles=@siFiles
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Account_Extra]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

Create Proc [dbo].[USP_Select_Account_Extra]( @siFiles int ) AS
begin
	 Select siAccount,FactorDate from AccountTable
	 where siFiles = @siFiles and ISNULL(IsExtra,0) = 1
end
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Account_HasAccountExtra]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_Select_Account_HasAccountExtra]( @siFiles int ) AS
begin
	SELECT
		ISNULL((Select top 1 1 from AccountTable where siFiles = @siFiles and IsExtra =0),0) as HasAccount,
		ISNULL((Select top 1 1 from AccountTable where siFiles = @siFiles and IsExtra =1),0) as HasExtra
end;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AccountTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_AccountTable] AS 
Begin
 Select  
	siAccount,siFiles,siDiscount,PerDiscount,Discount,TotalPrice,PayableFee,PaidAmount,RemainAmount,PaidDate,Type,Comment
 From AccountTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AccountTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_AccountTable_BySerial](@siAccount int) AS 
Begin 
 Select  
	siAccount,siFiles,siDiscount,PerDiscount,Discount,TotalPrice,PayableFee,PaidAmount,RemainAmount,RoundAmount,PaidDate,Type,Comment
 From AccountTable
 Where siAccount= @siAccount
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AccountTable_BySiAccount]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_AccountTable_BySiAccount]( @siAccount int ) AS             
Begin             
 Select              
  siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount, RemainAmount,       
  RoundAmount, PaidDate, Type, Comment, PerDiscount,Discount, FactorDate,    
  DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft, Used_PreCost, Used_PaidAfter, Used_SendType,       
  Used_BefTariff, Used_BefAmount, Used_AftTariff, Used_AftAmount  
 From AccountTable            
 Where siAccount= @siAccount       
End 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AccountTable_BySiFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Select_AccountTable_BySiFiles]( @siFiles int, @IsExtra tinyint ) AS           
Begin           
 Select            
  siAccount, siFiles, siDiscount, TotalPrice, PayableFee, PaidAmount, RemainAmount,     
  RoundAmount, PaidDate, Type, Comment, PerDiscount,Discount, FactorDate,  
  DiscountTitle, T_F, T_O, T_B, T_A,Used_Location, Use_Bef_Aft, Used_PreCost, Used_PaidAfter, Used_SendType,     
  Used_BefTariff, Used_BefAmount, Used_AftTariff, Used_AftAmount
 From AccountTable          
 Where siFiles= @siFiles  and ISNULL(IsExtra,0) = ISNULL(@IsExtra,0)    
End      
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AfterPrice]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Select_AfterPrice] AS 
Begin 
 Select Price  From CommonTariffTable  Where IsAfter= 1
End;


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_AlbumBysiFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_Select_AlbumBysiFiles](@siFiles int,@AlbumName varchar(50)) AS
select 
   ISNULL(siAlbum ,0) siAlbum  
 from AlbumTable 
 where (siFiles = @siFiles) and ( AlbumName = @AlbumName )







GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Albums_NotEmpty_BysiFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE  Proc  [dbo].[USP_Select_Albums_NotEmpty_BysiFile] (@siFiles int) AS
  Select Distinct  
     ALT.siAlbum,AlbumName,siDocument    
	FROM AlbumTable ALT 
	LEFT JOIN  DocumentTable DT ON ALT.siAlbum = DT.siAlbum       
    WHERE
	typeNumber = 0 and siFiles = @siFiles
    ORDER BY ALT.sialbum




GO

/****** Object:  StoredProcedure [dbo].[USP_Select_BoxInfoTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Select_BoxInfoTable] AS 
 Select  
	siBoxInfo,siPage,Grp,Type,Xmargin,Ymargin,Status
 From BoxInfoTable



GO

/****** Object:  StoredProcedure [dbo].[USP_Select_BoxInfoTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Select_BoxInfoTable_BySerial](@siBoxInfo int) AS 
 Select  
	siBoxInfo,siPage,Grp,Type,Xmargin,Ymargin,Status
 From BoxInfoTable
 Where siBoxInfo= @siBoxInfo



GO

/****** Object:  StoredProcedure [dbo].[USP_Select_BoxInfoTable_BySiPage]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Select_BoxInfoTable_BySiPage](@siPage int) AS 
 Select  
	siBoxInfo,siPage,Grp,Type,Xmargin,Ymargin,Status
 From BoxInfoTable
 Where siPage= @siPage




GO

/****** Object:  StoredProcedure [dbo].[USP_Select_CommonTariffTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Select_CommonTariffTable] AS 
Begin
 Select  
	siCommonTariff,TariffName,Price,Type,IsAfter,Countable,Comment
 From CommonTariffTable
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_CommonTariffTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Select_CommonTariffTable_BySerial](@siCommonTariff  int) AS 
Begin 
 Select  
	siCommonTariff,TariffName,Price,Type,IsAfter,Countable,Comment
 From CommonTariffTable
 Where siCommonTariff= @siCommonTariff
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_CommonTariffTable_NoTEB_ByWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_Select_CommonTariffTable_NoTEB_ByWait]( @siWait int ) AS      
BEGIN      
 SELECT TOP 10000000000      
   TT.siCommonTariff, TariffName, Price, TT.Type, IsAfter, Countable,      
   siServiceTable, siFiles, siWait, Number, ISNULL(Number,0)*Price AS Fee                          
 FROM VW_Select_CommonTariffTable_NoTEB TT      
 LEFT JOIN  ServiceTable ST 
 ON ST.siCommonTariff = TT.siCommonTariff AND ST.siWait = @siWait
 ORDER BY SeqNO,IsAfter
END      
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_CommonTariffTable_TEB_ByWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_CommonTariffTable_TEB_ByWait]( @siWait int ) AS      
BEGIN      
 SELECT       
   TT.siCommonTariff, TariffName, Price, TT.Type, IsAfter, Countable,      
   siServiceTable, siFiles, siWait, Number, ISNULL(Number,0)*Price AS Fee                          
 FROM VW_Select_CommonTariffTable_TEB TT      
 LEFT JOIN  ServiceTable ST ON ST.siCommonTariff = TT.siCommonTariff AND ST.siWait = @siWait      
END    
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_CommonTariffTable_Type2_BysiFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_CommonTariffTable_Type2_BysiFile]( @siFile int ) AS        
BEGIN        
 SELECT         
   TT.siCommonTariff, TariffName, Price, TT.Type, IsAfter, Countable,        
   siServiceTable, siFiles, siWait, Number, ISNULL(Number,0)*Price AS Fee                            
 FROM VW_Select_CommonTariffTableType2 TT        
 LEFT JOIN ServiceTable ST ON ST.siCommonTariff = TT.siCommonTariff AND ST.siFiles = @siFile        
END 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_DiscountTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_DiscountTable] AS   
Begin  
 Select    
	 siDiscount, Title, PerDiscount,'Title2'=Title+'   %'+Cast(PerDiscount AS varchar(4)), Comment  
 From DiscountTable  
End;  


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_DiscountTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_DiscountTable_BySerial]( @siDiscount int ) AS 
Begin
 Select  
	siDiscount, Title, PerDiscount, Comment
 From DiscountTable
 WHERE siDiscount = @siDiscount
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Doctor_EMail]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROC [dbo].[USP_Select_Doctor_EMail]( @Mode int) AS
BEGIN
	SELECT	TOP 10000000000 
		siDoctors, FileID, FName, LName, Job, Address1, Address2, Address3, Address4, 
		Comment, Tag1, Tag2, Tag3, Tag4, PerDiscount, SumAfter, FolderName, 
		EMail1, EMail2, SMS1,SMS2,IsActiveEMail,IsActiveSMS,
		TelegramLab,IsActiveTelegLab,TelegramTeb,IsActiveTelegTeb,
		'FullName'= ISNULL(LName,'')+' '+ISNULL(FName,'')+' ('+Job+')'+ CAST(FileID as varchar(10)),
		IsAuto,
		Filter,
		EMailLab1,
		EMailLab2,
		IsActiveEmailLab
	FROM DoctorsTable
	WHERE
		(@Mode = 0)
		OR
		(@Mode=1 AND ( ISNULL(LTRIM(RTRIM(EMail1)) ,'')<>'' OR ISNULL(LTRIM(RTRIM(EMail2)) ,'')<>''  OR ISNULL(LTRIM(RTRIM(SMS1)) ,'')<>''  OR ISNULL(LTRIM(RTRIM(SMS2)) ,'')<>'' ) ) -- Has EMail OR SMS
		OR
		(@Mode=2 AND ISNULL(LTRIM(RTRIM(EMail1)) ,'')='' AND ISNULL(LTRIM(RTRIM(EMail2)) ,'')=''  AND ISNULL(LTRIM(RTRIM(SMS1)) ,'')=''  AND ISNULL(LTRIM(RTRIM(SMS2)) ,'')='') -- Has not EMail OR SMS
	ORDER BY LName, FName
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Doctor_Reference_Info]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Doctor_Reference_Info]( @DoctorFileID int ) AS
BEGIN
	SELECT TOP 100000
		ALT.siAlbum, ALT.AlbumName, ALT.Comment 
	FROM CosmoDoc.dbo.AlbumTable ALT
	INNER JOIN  CosmoDoc.dbo.FilesTable FT ON ALT.siFiles = FT.siFiles
	WHERE FileID = @DoctorFileID
	ORDER BY siAlbum
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_DoctorsTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_DoctorsTable] AS 
Begin
 Select  
	siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4
 From DoctorsTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_DoctorsTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_DoctorsTable_BySerial](@siDoctors  int) AS         
Begin         
  Select          
   DC.siDoctors,FileID,FName,LName,Job,      
   Address1,Address2,Address3,Address4,DC.Comment,Tag1,Tag2,Tag3,Tag4,        
   PerDiscount,SumAfter,FolderName,MedicalID,      
   'FullName' =  LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') )),        
   'Full_Name' =  LTrim(RTrim( ISNULL(FName,'') +'  '+ ISNULL(LName,'') )), 
   ForceAfter
  From DoctorsTable DC       
  Left Join PrivateTariffTable PT ON DC.siDoctors = PT.siDoctors
  Where DC.siDoctors= @siDoctors        
End        
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_DoctorsTable_Full_Tarrif]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





CREATE Proc [dbo].[USP_Select_DoctorsTable_Full_Tarrif]( @Trf tinyint) AS 
begin

	IF @Trf = 0
	begin
		Select  
			siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4,FullName 
		From VW_Select_DoctorsTable_Full
	end
	else
	IF @Trf = 1
	begin
		Select  
			siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4,FullName 
		From VW_Select_DoctorsTable_Full F
		where F.siDoctors in( select siDoctors from PrivateTariffTable)
		
	end
	IF @Trf = 2
	begin
		Select  
			siDoctors,FileID,FName,LName,Job,Address1,Address2,Address3,Address4,Comment,Tag1,Tag2,Tag3,Tag4,FullName 
		From VW_Select_DoctorsTable_Full F
		where F.siDoctors not in( select siDoctors from PrivateTariffTable)
	end
end

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Document_Image]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE Proc [dbo].[USP_Select_Document_Image]( @siDocument int) AS 
 Select  
	siDocument,Document
 From DocumentTable
 Where siDocument=@siDocument


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_EMailForPatient]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_EMailForPatient]( @siFiles int ) AS
BEGIN
              
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
	

SELECT
   siWait, siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
   Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
   FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
   siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
   IsActiveEMail, EMail1, EMail2, TelegramStatus
FROM(
		 SELECT               
		   siWait, HPT.siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		   Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName,siBranch,BranchName, 
		   'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), FullName, HPT.WaitCheck, HPT.MachineCheck,      
		   SendType,SendStatus,MachinePhoto,ISNULL(Edited,0) Edited,ISNULL(Printed,0) Printed,
		   'EditedTitle' =CASE ISNULL(Edited,0)  WHEN 0 THEN NULL ELSE  N'صادر شد' END ,-- برگه ويرايش
		   'PrintedTitle'=CASE ISNULL(Printed,0) WHEN 0 THEN NULL ELSE N'چاپ شد'   END , -- ليبل
		   'Finished'  	 =CASE WHEN ISNULL(Edited,0) = 1 AND ISNULL(Printed,0) = 1 THEN 1 ELSE 0  END ,-- آماده ايميل
		   HPT.SentEMail,HPT.EMailDate,HPT.EMailTime,HPT.AttachedCount,HPT.SentSMS,
		   Case ISNULL(SentEMail,0) 
						WHEN 0 THEN NULL
						WHEN 1 THEN N'صف'
						WHEN 2 THEN N'Failed'
						WHEN 3 THEN N'ارسال'
			END SentEMailTitle,-- ايميل
		   CASE ISNULL(SentSMS,0) WHEN 0 THEN NULL ELSE  N'ارسال' END SentSMSTitle,-- SMS
		   HPT.IsActiveEMail, HPT.EMail1, HPT.EMail2,
		   'TelegramStatus'=
				   CASE AutoOrManual 
					   WHEN 'A' THEN TelegramStatus
					   WHEN 'M' THEN  ManualTelegStatus
				   END 
		 FROM  VW_Select_WaitList_Doc_Hospital HPT 
		 INNER JOIN AlbumTable ALT ON HPT.siFiles = ALT.siFiles
		 WHERE 
			  HPT.siFiles = @siFiles  AND  
			  ( Status = 16 ) AND
			  ISNULL(Printed,0)=1 AND 
			  ISNULL(Edited,0)=1 
	) Tbl

END 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_EMailLab_Ready]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROC [dbo].[USP_Select_EMailLab_Ready] AS
BEGIN
	WITH CTE AS
	(
	SELECT 
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SentEMailLabTime,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		EmailLab1,EmailLab2,
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	WHERE 
		IsActiveEmailLab =1 and 
		(EMailLab1 is not NULL OR EMailLab2 is not NULL ) and
		fCode is not null and 
		status =3  and 
		ISNULL(SentEMailLab,0) in( 0,2) -- New, Faild 
	)
	SELECT TOP 1 
		FileID,fCode,FName,LName,Mobile,MiladiDate,ReferDate,DoctorName,Status,
		TelegramStatus,TelegMessageId,TelegramLab,TryCount,PdfPath,
		PdfNetwork,
		EmailLab1,EmailLab2,TitleContent,
		PatientFullName = Concat(FName,' ',LName) 
	FROM CTE A
	WHERE 
		ISNULL( DATEDIFF(Minute, SentEMailLabTime, Getdate()),999)>=5
		and DATEDIFF(Day, MiladiDate, Getdate()) <=( Select top 1 EmailLabDay from ConfigTable) 
	ORDER BY TryCount,SentEMailLabTime,FileID 
END
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_EMailLab_Ready_OLD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROC [dbo].[USP_Select_EMailLab_Ready_OLD] AS
BEGIN
	WITH CTE AS
	(
	SELECT
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SentEMailLabTime,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		EmailLab1,EmailLab2,
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN FilesTable FT ON FT.FileID = TP.FileID
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor
	WHERE 
		IsActiveEmailLab =1 and 
		(EMailLab1 is not NULL OR EMailLab2 is not NULL ) and
		fCode is not null and 
		status =3  and 
		ISNULL(SentEMailLab,0) in( 0,2) -- New, Faild 
	UNION
	SELECT 
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SentEMailLabTime,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		EmailLab1,EmailLab2,
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	WHERE 
		IsActiveEmailLab =1 and 
		(EMailLab1 is not NULL OR EMailLab2 is not NULL ) and
		fCode is not null and 
		status =3  and 
		ISNULL(SentEMailLab,0) in( 0,2) -- New, Faild 
	)
	SELECT TOP 1 
		FileID,fCode,FName,LName,Mobile,MiladiDate,ReferDate,DoctorName,Status,
		TelegramStatus,TelegMessageId,TelegramLab,TryCount,PdfPath,
		--'\\DBSERVER\NovinPDF\13973767.pdf' as
		 PdfNetwork,
		EmailLab1,EmailLab2,TitleContent,
		PatientFullName = Concat(FName,' ',LName) 
	FROM CTE A
	WHERE 
		ISNULL( DATEDIFF(Minute, SentEMailLabTime, Getdate()),999)>=5
		and DATEDIFF(Day, MiladiDate, Getdate()) <=( Select top 1 EmailLabDay from ConfigTable) 
	ORDER BY TryCount,SentEMailLabTime,FileID 
END
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Extra_By_siFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_Select_Extra_By_siFiles]( @siFiles as int) AS
begin
-- siCommonTariff,TariffName,Price,Type,IsAfter,ExtraPercent,ForceExtra,Bef_Aft,Number,Number2
	SELECT 
		    ST.siServiceTable,  
			CT.siCommonTariff,
			CT.TariffName,
			CT.Price - (CT.Price* ISNULL(CT.ExtraPercent,0)/100) as Price ,
			CT.Type,
			CT.IsAfter,
			ISNULL(CT.ExtraPercent,0) ExtraPercent,
			CT.ForceExtra,
			FT.Bef_Aft,
			ST.Number Number,
			ISNULL(ST.Number,1) Number2
	FROM CommonTariffTable CT
	Left join ServiceTable  ST ON ST.siCommonTariff = CT.siCommonTariff
	Left join FilesTable FT ON FT.siFiles =  ST.siFiles
	where   ( CT.Type <> 1 ) AND
			( ST.siFiles = @siFiles  OR  ForceExtra = 1 ) AND 
			( Bef_Aft IS NULL OR Bef_Aft =1 OR ( Bef_Aft = IsAfter )  )
end;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_File_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [dbo].[USP_Select_File_BySerial]( @siFiles int ) AS       
select        
  siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,thumb,Bef_Aft, siHospital,    
  Comment,Address,Age,SendType,DoctorName,Job,RefFileID, 'FullName' = LTrim(RTrim(ISNULL(FName,'') +'  '+LName))  ,Sex
 from FilesTable      
 where sifiles = @siFiles
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_File_Info_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [dbo].[USP_Select_File_Info_BySerial]( @siFiles int ) AS       
select        
  siFiles,FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,    
  Comment,Address,Age,SendType,DoctorName,Job,siDoctor,RefFileID,Sex    
 from FilesTable      
 where sifiles = @siFiles    

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FileReceiptBysiFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FileReceiptBysiFiles](@siFiles int) AS
BEGIN
	SELECT 
		-1 CatLevel,0 TopCat, 0 SubCat1, 0 SubCat2, ISNULL(BackColor,1) BackColor, ISNULL(LifeSize,0) LifeSize,ISNULL(GridLine,0) GridLine, Comment1, Comment2
	FROM FileReceiptTable 
	WHERE siFiles= @siFiles
	UNION ALL
	SELECT 
		0 CatLevel,TopCat.value('F[1]','Varchar(100)') , 0,0,0,0,0, NULL, NULL
	FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
	CROSS APPLY A.TopCategory.nodes('T') Tbl(TopCat)
	WHERE siFiles= @siFiles
	UNION ALL
	SELECT 
		1,0, SubCat1.value('F[1]','Varchar(100)') , SubCat1.value('F[2]','Varchar(100)') ,0,0,0, NULL, NULL
	FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
	CROSS APPLY A.SubCategory1.nodes('T') Tbl(SubCat1)
	WHERE siFiles= @siFiles
	UNION ALL
	SELECT 
		2,0, SubCat2.value('F[1]','Varchar(100)') , SubCat2.value('F[2]','Varchar(100)') ,0,0,0, NULL, NULL
	FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
	CROSS APPLY A.SubCategory2.nodes('T') Tbl(SubCat2)
	WHERE siFiles= @siFiles
	ORDER BY 1,2,3,4
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesByID]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





CREATE Proc [dbo].[USP_Select_FilesByID](@FileID int ) AS  
select   
    ISNULL(siFiles,0) siFiles   
   from FilesTable  
 where FileID = @FileID


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesInfo_ForPrint]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesInfo_ForPrint](  @siFiles Int  ) AS         
BEGIN
	SELECT 
	   FT.siFiles, ALT.AssurList as FileID, FT.FName, FT.LName, Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,
      'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN N'قبل از درمان' ELSE N'بعد از درمان' END ,  
	   Case When Printed IS NULL then 1 else 0 end as IsFirstPrint,
	   siHospital,      
	   Subject,Address,Age,SendType,DoctorName,  RefFileID,siDoctor,PathFolder, 
	   'FullName' = LTrim(RTrim( ISNULL(FT.LName,'') +'  '+ ISNULL(FT.FName,'') ))  ,
	   'Full_NamePatient' = LTrim(RTrim( ISNULL(FT.FName,'') +'  '+ ISNULL(FT.LName,'') )) , Sex ,siBranch ,
	   ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'') as DoctorFullName
	FROM FilesTable FT
	Inner Join DoctorsTable DT ON FT.siDoctor = DT.siDoctors
	Left Join AlbumTable ALT ON FT.siFiles = ALT.siFiles
	inner join WaitTable WT ON WT.siFiles = FT.siFiles
	WHERE FT.siFiles = @siFiles
 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_Without_Thumb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesTable_Without_Thumb]( @BranchView nvarchar(100), @siFiles Int, @Location nvarchar(5) ) AS         
BEGIN
--DECLARE @BranchView nvarchar(100)=',1,2', @siFiles Int= 67883, @Location nvarchar(5) ='P';
	--F = First; L= Last; P=perrior; N= Next ; C = Current
	DECLARE @RowStatus nvarchar(2)='',@RowNO Int= -1, @MinRowNO Int=-1, @MaxRowNO Int=-1, @CsiFiles Int=-1;
 
	SELECT  
		'RowNO'= ROW_NUMBER() OVER( ORDER BY siFiles),
		'CsiFiles'= siFiles
	INTO #FilesTable
	FROM FilesTable FT    
	WHERE  
	   ( ISNULL(@BranchView,'0') ='0' OR siBranch IN ( SELECT Item FROM  dbo.FN_StringToTable(@BranchView, ',')))
 
	SELECT 	@MinRowNO=MIN(RowNO), @MaxRowNO= MAX(RowNO) FROM #FilesTable
 
	Select @RowNO= RowNO from #FilesTable WHERE CsiFiles = @siFiles
 
	IF @RowNO = -1 
	BEGIN
		SELECT @CsiFiles = CsiFiles,@RowNO = RowNO  FROM #FilesTable A
		WHERE 
			(@Location = 'C' AND A.CsiFiles=( SELECT  MAX(CsiFiles) FROM #FilesTable WHERE CsiFiles<= @siFiles) ) OR
			(@Location = 'P' AND A.CsiFiles=( SELECT  MAX(CsiFiles) FROM #FilesTable WHERE CsiFiles<  @siFiles) ) OR
			(@Location = 'N' AND A.CsiFiles=( SELECT  MIN(CsiFiles) FROM #FilesTable WHERE CsiFiles>  @siFiles) ) 
 
		IF @CsiFiles IS NULL 
			SELECT @CsiFiles = CsiFiles, @RowNO = RowNO FROM #FilesTable
			WHERE RowNO=
					CASE @Location 
						WHEN 'F' THEN @MinRowNO
						WHEN 'P' THEN @MinRowNO
						WHEN 'C' THEN @MaxRowNO
						WHEN 'N' THEN @MaxRowNO
						WHEN 'L' THEN @MaxRowNO
					END
	END 
	ELSE
	BEGIN
		SELECT @CsiFiles = CsiFiles, @RowNO = RowNO	 FROM  #FilesTable
		WHERE 
			( @Location = 'F' AND RowNO = @MinRowNO )
			OR
			( @Location = 'P' AND RowNO = CASE WHEN @RowNO-1 < @MinRowNO THEN @MinRowNO ELSE @RowNO-1 END )
			OR
			( @Location = 'C' AND RowNO = @RowNO )
			OR
			( @Location = 'N' AND RowNO = CASE WHEN @RowNO+1 > @MaxRowNO THEN @MaxRowNO ELSE @RowNO+1 END )
			OR
			( @Location = 'L' AND RowNO = @MaxRowNO )
	END
	
	IF @RowNO = @MinRowNO SET @RowStatus = @RowStatus+'F';  
	IF @RowNO = @MaxRowNO SET @RowStatus = @RowStatus+'L';  
 
 
	SELECT 
	   siFiles,FileID,FName,LName,Phone1,Phone2, RefPlace,PaidAfter,BirthYear,ReferDate,Bef_Aft,siHospital,      
	   Subject,Comment,Address,Age,SendType,DoctorName,Job, RefFileID,siDoctor,PathFolder, 
	   'FullName' = LTrim(RTrim( ISNULL(LName,'') +'  '+ ISNULL(FName,'') ))  ,
	   'Full_NamePatient' = LTrim(RTrim( ISNULL(FName,'') +'  '+ ISNULL(LName,'') )) , Sex ,siBranch 
	   , @RowNO as RowNO
	   , @RowStatus as RowStatus
	   ,Is3D
	FROM FilesTable FT
	WHERE siFiles = @CsiFiles
 
	BEGIN TRY DROP TABLE #FilesTable END TRY BEGIN CATCH END CATCH
 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_WithThumb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesTable_WithThumb](                      
  @FileID int,@FName varchar(15),@LName varchar(25),@PaidAfter int,@BirthYearFrom varchar(4),@BirthYearTo varchar(4),                      
  @Phone varchar(100), @ReferDateFrom varchar(10), @ReferDateTo varchar(10), @Subject varchar(200),                       
  @Comment varchar(4000), @Address varchar(200), @Album int, @AgeFrom int, @AgeTo int , @Marry int,        
  @DoctorName varchar(50), @Job varchar(50),@siDoctor int , @siHospital int, @SI int, @BranchView nvarchar(100) ) AS                      
BEGIN                     
 IF @PaidAfter not in (0,1)                    
    SET @PaidAfter = NULL                      
 IF @Marry not in (0,1)                    
    SET @Marry = NULL                      
 Select  TOP (ISNULL( (select Top 1 TopSelect From MachineTable Where SI = @SI) ,1000000000)) --Percent 
  FT.siFiles,FT.FileID,FT.FName,FT.LName,Phone1,Phone2,PaidAfter,BirthYear,ReferDate,Subject,thumb,  
  FT.Comment,Address,Age,DoctorName,FT.Job,RefFileId,ALT.SurgDate,SendType,  
  'SendTypeName'=CASE SendType WHEN 0 THEN 'اورژانس' ELSE 'عادي' END ,  
  'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN 'Bef' ELSE 'Aft' END ,  
  'AllName' = LTRIM(RTRIM( FT.LName +' '+ ISNULL(FT.FName,'') ))  ,  
  'PaidAfterStatus'= CASE PaidAfter when 0 then NULL else 'پرداخت شد' end,
  Is3D ,CASE Is3d When 0 then NULL else '3D' end Is3DTitle                  
 From FilesTable FT   
 LEFT JOIN AlbumTable ALT  ON ALT.siFiles = FT.siFiles  
  Where                       
   (( @BranchView ='0' or @BranchView =',0,' or  (PATINDEX('%,'+CAST(siBranch as varchar(2))+',%',@BranchView)>0) )) AND
   ((@BirthYearFrom IS NULL ) or ( BirthYear >= @BirthYearFrom )) AND                      
   ((@BirthYearTo IS NULL ) or ( BirthYear <= @BirthYearTo )) AND                      
   ((@AgeFrom IS NULL ) or ( Age >= @AgeFrom )) AND                      
   ((@AgeTo IS NULL ) or ( Age <= @AgeTo )) AND                      
   ((@siDoctor IS NULL ) or ( siDoctor = @siDoctor )) AND                      
   ((@siHospital IS NULL ) or ( siHospital = @siHospital )) AND                      
   ((@FileID IS NULL ) or ( FT.FileID = @FileID )) AND                      
   ((@PaidAfter IS NULL ) or ( PaidAfter = @PaidAfter )) AND                      
   ((@Marry IS NULL ) or ( SendType = @Marry )) AND                      
   ( ((@Phone IS NULL ) or ( Phone1  Like @Phone )) or                      
     ((@Phone IS NULL ) or ( RefPlace  Like @Phone ))  )AND                      
   ((@FName  IS NULL ) or ( FT.FName  Like '%'+@FName+'%' )) AND                      
   ((@LName  IS NULL ) or ( FT.LName  Like '%'+@LName+'%' )) AND                      
   ((@Subject IS NULL )or ( Subject Like '%'+@Subject+'%' )) AND                      
   ((@Comment IS NULL )or ( FT.Comment Like '%'+@Comment+'%' )) AND                      
   ((@Address IS NULL )or ( Address Like '%'+@Address+'%' )) AND                      
   ((@DoctorName IS NULL )or ( DoctorName Like '%'+@DoctorName+'%' )) AND                      
   ((@Job IS NULL )or ( FT.Job Like '%'+@Job+'%' )) AND                      
   ((@ReferDateFrom IS NULL ) or ( ReferDate >= @ReferDateFrom )) AND                      
   ((@ReferDateTo   IS NULL ) or ( ReferDate <= @ReferDateTo )) AND            
   (            
     (@Album = 2) or -- All Albums               
     ((@Album = 0) and ( FT.siFiles      in (Select distinct sifiles from AlbumTable) )  ) or            
     ((@Album = 1) and ( FT.siFiles  not in (Select distinct sifiles from AlbumTable) )  )            
   )            
 ORDER BY ReferDate DESC,  FT.siFiles DESC
END  
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_WithThumb_Album]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesTable_WithThumb_Album](                      
  @AlbumName varchar(50),@AlbumDateFrom varchar(10),@AlbumDateTo varchar(10),                  
  @SurgDateFrom varchar(10),@SurgDateTo varchar(10),@AlbumComment varchar(200),        
  @SurgList varchar(4000),@AssurList varchar(200),@Remain int,@SI int, @BranchView nvarchar(100)  ) AS                      
BEGIN                  
 Select Distinct FT.siFiles into #TempFiles                  
 From FilesTable FT                  
 inner join  AlbumTable ALT on FT.siFiles = ALT.siFiles                  
 Left join AlbumSurgTable AST on ALT.siAlbum = AST.siAlbum                  
 Where                       
   (( @BranchView ='0' or @BranchView =',0,' or  (PATINDEX('%,'+CAST(siBranch as varchar(2))+',%',@BranchView)>0) )) AND
   (( @AlbumName IS NULL ) or ( AlbumName Like '%'+@AlbumName+'%' )) AND                      
   (( @AssurList IS NULL ) or ( ALT.AssurList Like '%'+@AssurList+'%' )) AND                      
   (( @AlbumComment IS NULL ) or ( ALT.Comment Like '%'+@AlbumComment+'%' )) AND                      
   (( @AlbumDateFrom IS NULL) or ( AlbumDate >= @AlbumDateFrom )) AND                      
   (( @AlbumDateTo   IS NULL) or ( AlbumDate <= @AlbumDateTo )) AND                  
   (( @SurgDateFrom IS NULL) or ( SurgDate >= @SurgDateFrom )) AND                      
   (( @SurgDateTo   IS NULL) or ( SurgDate <= @SurgDateTo )) AND                  
   (( @SurgList IS NULL) or (PATINDEX('%,'+CAST(siSurgery as varchar(2))+',%',@SurgList)>0) )                  
         
 
  Select Distinct         
    TF.siFiles , Sum(ISNULL(Remain,0)) as RemainPay into #TEMP              
  From #TempFiles TF                  
  inner join  AlbumTable ALT on TF.siFiles = ALT.siFiles         
  Group by  TF.siFiles              
  Having ( @Remain = 0  ) or (Sum(ISNULL(Remain,0)) > 0)        
               
  Select TOP (ISNULL( (select Top 1 TopSelect From MachineTable Where SI = @SI) ,1000000000)) --Percent     
    RemainPay,                       
    FT.siFiles,FileID,FName,LName,Phone1,Phone2,PaidAfter,BirthYear,ReferDate,Subject,              
    thumb,FT.Comment,Address,Age,SendType,DoctorName,Job,RefFileID,ALT.SurgDate,          
    'SendTypeName'=CASE SendType WHEN 0 THEN 'اورژانس' ELSE 'عادي' END ,      
    'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN 'Bef' ELSE 'Aft' END ,      
    'AllName' = LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,'PaidAfterStatus'= Case PaidAfter when 0 then NULL else 'پرداخت شد' end,
	Is3D,CASE Is3d When 0 then NULL else '3D' end Is3DTitle
   From FilesTable FT        
   LEFT JOIN AlbumTable ALT  ON ALT.siFiles = FT.siFiles      
   INNER  JOIN #TEMP T on T.siFiles = FT.siFiles        
   ORDER BY ReferDate DESC,  FT.siFiles  DESC
            
 drop Table #Temp        
 drop Table #TempFiles        
 
END  
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_WithThumb_ByLetter]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  PROC [dbo].[USP_Select_FilesTable_WithThumb_ByLetter]( @letter varchar(1), @SI int, @BranchView nvarchar(100)) AS           
BEGIN
	Select  TOP (ISNULL( (select Top 1 TopSelect From MachineTable Where SI = @SI) ,1000000000)) --Percent 
	  FT.siFiles,FT.FileID,FT.FName,FT.LName,Phone1,Phone2,PaidAfter,BirthYear,ReferDate,Subject,--thumb,  
	  FT.Comment,Address,Age,DoctorName,FT.Job,RefFileId,ALT.SurgDate,SendType,  
	  'SendTypeName'=CASE SendType WHEN 0 THEN 'اورژانس' ELSE 'عادي' END ,  
	  'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN 'Bef' ELSE 'Aft' END ,  
	  'AllName' = LTRIM(RTRIM( FT.LName +' '+ ISNULL(FT.FName,'') ))  ,  
	  'PaidAfterStatus'= CASE PaidAfter when 0 then NULL else 'پرداخت شد' end 
	  , Is3D
	  , CASE Is3d When 0 then NULL else '3D' end Is3DTitle
	 From FilesTable FT   
	 LEFT JOIN AlbumTable ALT  ON ALT.siFiles = FT.siFiles  
	 Where ( @letter is NULL  or LName Like @letter+'%' ) AND 
		   ( @BranchView ='0' or @BranchView =',0,' or  (PATINDEX('%,'+CAST(siBranch as varchar(2))+',%',@BranchView)>0) )
	 ORDER BY ReferDate DESC, siFiles desc      
END;
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_WithThumb_Doc]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesTable_WithThumb_Doc](                
  @Title varchar(50),@DocComment varchar(200),@TypeList varchar(4000),@SI  int, @BranchView nvarchar(100)) AS                
BEGIN            
 Select Distinct FT.siFiles into #TEMP            
 From FilesTable FT            
 inner join  AlbumTable ALT on FT.siFiles = ALT.siFiles            
 inner join  DocumentTable DT on ALT.siAlbum = DT.siAlbum            
 Where                 
   (( @BranchView ='0' or @BranchView =',0,' or  (PATINDEX('%,'+CAST(siBranch as varchar(2))+',%',@BranchView)>0) )) AND
   ((@Title IS NULL ) or ( Title Like '%'+@Title+'%' )) AND                
   ((@DocComment IS NULL ) or ( DT.Comment Like '%'+@DocComment+'%' )) AND                
   ((@TypeList IS NULL) or (PATINDEX('%,'+CAST(TypeNumber as varchar(2))+',%',@TypeList)>0) )            
            
 Select  TOP (ISNULL( (select Top 1 TopSelect From MachineTable Where SI = @SI) ,1000000000)) --Percent     
  FT.siFiles,FileID,FName,LName,Phone1,Phone2,PaidAfter,BirthYear,ReferDate,Subject,             
  thumb,FT.Comment,Address,Age,SendType,DoctorName,Job,RefFileID,ALT.SurgDate,        
  'SendTypeName'=CASE SendType WHEN 0 THEN 'اورژانس' ELSE 'عادي' END ,      
  'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN 'Bef' ELSE 'Aft' END ,      
  'AllName' = LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,'PaidAfterStatus'= Case PaidAfter when 0 then NULL else 'پرداخت شد' end,
  Is3D,CASE Is3d When 0 then NULL else '3D' end Is3DTitle
 From FilesTable FT  
 LEFT JOIN AlbumTable ALT  ON ALT.siFiles = FT.siFiles      
 where FT.siFiles in (select siFiles From #Temp)             
 ORDER BY ReferDate DESC,  FT.siFiles DESC   
END   
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FilesTable_WithThumb_ForCheck]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FilesTable_WithThumb_ForCheck]( @siPage int , @Pattern varchar(100) , @AndOR varchar(1) ) AS         
BEGIN    
 Select  distinct  
  FLT.siFiles, FileID into #Temp  
 from FilesTable FLT      
   Inner Join AlbumTable ALT   ON ALT.siFiles = FLT.siFiles    
   Inner Join DocumentTable DT ON ALT.siAlbum = DT.siAlbum    
   where (typeNumber = 9) and (siPage = @siPage ) and dbo.PatternCheck( DT.CheckValue,@Pattern,@AndOR )=1    
 ORDER BY FileID DESC        
   
 Select  Top 100 Percent       
  FT.siFiles,FT.FileID,FName,LName,Phone1,Phone2,RefPlace,PaidAfter,BirthYear,ReferDate,Subject,        
  thumb,      
  Comment,Address,Age,SendType,DoctorName,Job,RefFileID,      
  'AllName' =LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,'PaidAfterStatus'= Case PaidAfter when 0 then NULL else 'پرداخت شد' end        
   from FilesTable FT  
   Inner Join #TEMP ON #Temp.siFiles = FT.siFiles  
  
 drop Table #Temp  
  
END  
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FirstLastRecord]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FirstLastRecord]( @BranchView nvarchar(100), @Location nvarchar(5) ) AS         
BEGIN
--DECLARE @BranchView nvarchar(100)=',1,2', @Location nvarchar(5) ='P';

	SELECT  
		'FsiFiles'= FIRST_VALUE(siFiles) OVER( ORDER BY ReferDate, siFiles ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
		'LsiFiles'= LAST_VALUE(siFiles) OVER( ORDER BY ReferDate, siFiles  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	FROM FilesTable FT    
	WHERE  
	   ( @BranchView ='0' OR siBranch IN ( SELECT Item FROM  dbo.FN_StringToTable(@BranchView, ',')))

END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_FromNovin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_FromNovin](@Date varchar(10),@FromTeb int) as
BEGIN
	--DECLARE @Date varchar(10)='1397/12/14',@FromTeb int=1
-- Compatible with Parsipol 0
 
;WITH CTE AS 
(
	SELECT 
		A.fcode,
		T.FileID,
		CONCAT(A.fLastName COLLATE SQL_Latin1_General_CP1256_CI_AS,' ', A.fFirstName COLLATE SQL_Latin1_General_CP1256_CI_AS) PatientName,
		CONCAT(B.fLastName COLLATE SQL_Latin1_General_CP1256_CI_AS,' ', B.fFirstName COLLATE SQL_Latin1_General_CP1256_CI_AS) DoctorName,
		CASE WHEN AutoStatus =2 THEN T.DoctorName ELSE NULL END as LinkedDoctor,
		T.siDoctor, 
		Cast(A.fcode as nvarchar(15)) as fCodeMonth,
		CASE A.fEmergency WHEN 0 THEN N'عادي' ELSE N'اورژانس' END SendStatus, 
		CASE A.fSex WHEN 0 THEN N'زن' ELSE N'مرد' END SexTitle, 
		A.fMobile  as Mobile,
		A.fAge  as Age, 
		B.fCodeNezamPezeshki,
		B.fFirstName,
		B.fLastName,
		A.fAcceptionDate as AcceptionDate, 
		A.fAcceptionDateTime,
		LEFT(fAcceptionTime,5) as AcceptionTime,
		DS.fName as Job,
		AutoStatus,
		CASE 
			--WHEN (T.RegisterDate IS NOT NULL) AND (Left(T.FileID,1)<>'9') THEN  N'طب نگار' 
			WHEN AutoStatus =1 THEN  N'Auto Link' 
			WHEN AutoStatus =2 THEN  N'Manual Link'
			WHEN A.ReAccept =1 THEN  N'پذيرش مجدد'
			ELSE NULL 
		END LinkStatus,
		CASE 
			--WHEN (T.RegisterDate IS NOT NULL) AND (Left(T.FileID,1)<>'9') THEN  3 --طب نگار
			WHEN AutoStatus =1 THEN  1 --Auto Link
			WHEN AutoStatus =2 THEN  2 --Manual Link
			WHEN A.ReAccept =1 THEN  4
			ELSE 0 
		END LinkStatusCode
		,DT.MedicalId, CONCAT(DT.FName,' ',DT.LName ) DoctorFullName
		,Case when AutoStatus in(1,2) Then IsTebDoc  Else NULL end IsTebDoc
	FROM NovinAcceptation A
	LEFT JOIN NovinDoctor B ON A.fCodeDoctor = B.fCode
	LEFT JOIN NovinSpecialty DS ON B.fCodeDoctorSpecialty = DS.fCode
	LEFT JOIN NovinTebnegarPatients T On T.fCode = A.fCode and T.RegisterDate IS NOT NULL
	LEFT JOIN DoctorsTable DT ON (T.siDoctor = DT.siDoctors)
	WHERE 
		fAcceptionDate = @Date and 
		(@FromTeb =0 OR T.siDoctor IS NULL ) AND
		A.fCancellation <> 1
)
SELECT 
	fCode,FileID,PatientName,DoctorName,LinkedDoctor,siDoctor,SendStatus,SexTitle,Mobile,Age,
	fCodeNezamPezeshki,fFirstName,fLastName,AcceptionDate,fAcceptionDateTime,AcceptionTime,Job,
	AutoStatus,LinkStatus,LinkStatusCode,MedicalId,DoctorFullName,IsTebDoc,fCodeMonth
FROM CTE
WHERE 
	(@FromTeb =0 OR AutoStatus IS NULL OR ( AutoStatus in (1,2) AND IsTebDoc =0 )) 
ORDER BY fAcceptionDateTime DESC 
	
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_HospitalsTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Select_HospitalsTable_BySerial](@siHospital  int) AS         
	SELECT  TOP 10000000000    
		siHospital, FullName, Type, Comment, Location, ForceAfter   
	FROM  HospitalTable    
	WHERE siHospital = @siHospital
	ORDER BY Location desc ,FullName    
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ListOfDoctors_Once]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_ListOfDoctors_Once]( @FileID int ) AS      
begin      
 Select       
 'Alias' = Cast(FileID as Varchar(20))+'-'+LName+' ' +FName +'-'+ Job +' -آدرس: '+Address1  ,    
 SumAfter,FolderName,IsTebDoc,   
 'Discount' = Case     
   When PerDiscount between 1 and 100 then Cast( PerDiscount as varchar(5))+'%'     
   else Cast(PerDiscount as varchar(5)) end    
  from CosmoPatient..DoctorsTable      
  where (@FileID IS NULL) OR (FileID = @FileID )      
  Order by FileID      
      
end      

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ListOfDocumentsInBank]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








Create Proc [dbo].[USP_Select_ListOfDocumentsInBank] AS
 select Distinct Path  from DocumentTable  where TypeNumber <> 0







GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ListOfDocumentsInBank_ByAlbum]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE Proc [dbo].[USP_Select_ListOfDocumentsInBank_ByAlbum]( @siAlbum int ) AS  
 select distinct  Path  
  from DocumentTable  where TypeNumber <> 0 and siAlbum = @siAlbum  








GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ListOfDocumentsInBank_ByFileID]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE Proc [dbo].[USP_Select_ListOfDocumentsInBank_ByFileID]( @FileID int ) AS  
Begin  
 Declare @ID varchar(50)  
 SET @ID = '%-'+ Cast( @FileID as varchar(50) )+'-%'  
 select distinct Path  
  from DocumentTable    
 where (TypeNumber <> 0) and (Path Like  @ID)  
  
End  








GO

/****** Object:  StoredProcedure [dbo].[USP_Select_listOfSurgeryByFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








Create Proc [dbo].[USP_Select_listOfSurgeryByFile]( @siFiles int ) AS
SELECT    Distinct
  FT.siFiles,ST.SurgeryName
FROM       FilesTable  FT 
INNER JOIN  AlbumTable ALT ON FT.siFiles = ALT.siFiles 
INNER JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum 
INNER JOIN  SurgeryTable ST ON AST.siSurgery = ST.siSurgery
where FT.siFiles = @siFiles
order by ST.SurgeryName







GO

/****** Object:  StoredProcedure [dbo].[USP_Select_listOfSurgeryByFile_String]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE Proc [dbo].[USP_Select_listOfSurgeryByFile_String]( @siFiles int ) AS    
BEGIN    
  SET NOCOUNT ON    
Declare @I int , @CNT int, @L int  
Declare @T varchar(1000),@Temp varchar(50)     
SELECT   DISTINCT   
   ST.SurgeryName   INTO #TEMP1  
FROM    FilesTable  FT     
INNER JOIN  AlbumTable ALT ON FT.siFiles = ALT.siFiles     
INNER JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum     
INNER JOIN  SurgeryTable ST ON AST.siSurgery = ST.siSurgery    
where FT.siFiles = @siFiles    
order by ST.SurgeryName desc    
  
SELECT   Distinct    
  identity(int,1,1) Row,SurgeryName   INTO #TEMP  
FROM  #TEMP1    
  
SET @CNT = @@ROWCOUNT    
SET @I = 1    
   
IF @CNT =0   
begin  
  SELECT NULL AS List  
  Return  
end   
  
SET @T=''    
  
while @I <= @CNT    
begin    
  SELECT @Temp = SurgeryName FROM #TEMP WHERE ROW = @I    
  SET @T = @Temp + ', ' + @T     
  SET @I = @I +1    
end    
  
 SET @L = Len(@T)    
  
 Select Left(@T,@L-1)  AS List  
  
drop Table #Temp    
drop Table #Temp1    
    
  SET NOCOUNT OFF    
    
END    








GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Mixed_Tables_WithThumb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Mixed_Tables_WithThumb]( 
  @FileIDFrom int, @FileIDTo int, @PaidAfter int, @ReferDateFrom varchar(10), @ReferDateTo varchar(10),         
  @SurgList varchar(4000), @SurgDateFrom varchar(10), @SurgDateTo varchar(10),       
  @Title varchar(50), @TypeList varchar(4000),  @AllComments1 varchar(4000) ,    @AllComments2 varchar(4000) ,        
  @SurgAndOr int , @CommentAndOr int, @SI int, @BranchView nvarchar(100)           
   ) AS          
BEGIN  
  --  @CommentAndOr (0 meanes AND)  --  (1 means OR)    
  --  @SurgAndOr    (0 meanes AND)  --  (1 means OR)    
  DECLARE @C int    
    
  SET @C = dbo.CountOfChar( @Surglist , ',' ) -1    
 
  --------------------------------------------------------------------------------------------                     
 
  IF @SurgList IS NULL      
     SET @C =1 -- Return All rows    
 
  IF @C = 1     
     SET @SurgAndOr = 1 -- set to OR mode    
 
 
  --------------------------------------------------------------------------------------------                     
 
  IF @AllComments1 IS NULL  -- The first parameter must be not null    
  BEGIN                     -- therefor exchange 2 values                               
     SET @AllComments1 = @AllComments2    
     SET @AllComments2 = NULL    
  END      
 
    
 
  IF @AllComments2 IS NULL    
     SET @CommentAndOr = 1 -- Set to OR mode    
 
-------  select Rows with All cretia but Comment condition ------------------------------------------      
 
  SELECT DISTINCT          
     FT.siFiles       
  INTO #TEMP1           
  FROM FilesTable FT         
  LEFT JOIN  AlbumTable ALT   ON FT.siFiles  = ALT.siFiles            
  LEFT JOIN  DocumentTable DT ON ALT.siAlbum = DT.siAlbum               
  LEFT JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum                      
    WHERE        
    ( @BranchView ='0' or @BranchView =',0,' or  (PATINDEX('%,'+CAST(siBranch as varchar(2))+',%',@BranchView)>0) ) AND
     (          
      (  @Title IS NULL  OR  Title Like '%'+@Title+'%'   ) AND                    
      (  @TypeList IS NULL OR PATINDEX('%,'+CAST(TypeNumber as varchar(2))+',%',@TypeList)>0 )                           
     )        
       AND            
     (            
      (  @FileIDFrom IS NULL  OR  FileID >= @FileIDFrom  ) AND                          
      (  @FileIDTo   IS NULL  OR  FileID <= @FileIDTo  ) AND          
      (  @PaidAfter = 2  OR  PaidAfter = @PaidAfter  ) AND                          
      (  @ReferDateFrom IS NULL  OR  ReferDate >= @ReferDateFrom  ) AND                          
      (  @ReferDateTo   IS NULL  OR  ReferDate <= @ReferDateTo  )    
     )                   
       AND         
     (                  
      (  @SurgDateFrom IS NULL OR  SurgDate >= @SurgDateFrom  ) AND                          
      (  @SurgDateTo   IS NULL OR  SurgDate <= @SurgDateTo    ) AND                      
      (  @SurgList IS NULL OR PATINDEX('%,'+CAST(siSurgery as varchar(2))+',%',@SurgList)>0 )                         
     )              
 
  GROUP BY  FT.siFiles         
  HAVING ( @SurgAndOr = 1 ) OR COUNT( DISTINCT siSurgery ) = @C    
    
 
-------  select Rows only Comment condition ------------------------------------------      
           
  SELECT DISTINCT          
     FT.siFiles into #TEMP2           
  FROM FilesTable FT         
  LEFT JOIN  AlbumTable ALT   ON FT.siFiles  = ALT.siFiles            
  LEFT JOIN  DocumentTable DT ON ALT.siAlbum = DT.siAlbum               
  LEFT JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum                      
    WHERE        
 
 CASE  @CommentAndOr          
 
  WHEN 0 THEN -- AND Condition       
    CASE      
    WHEN      
      ( @AllComments1 IS NULL  OR        
       DT.Comment  Like '%'+@AllComments1+'%'  OR        
       ALT.Comment Like '%'+@AllComments1+'%'  OR        
       FT.Comment  Like '%'+@AllComments1+'%' )       
     AND       
	  ( @AllComments2 IS NULL  OR       
       DT.Comment  Like '%'+@AllComments2+'%'  OR       
       ALT.Comment Like '%'+@AllComments2+'%'  OR       
       FT.Comment  Like '%'+@AllComments2+'%' )         
    THEN 'ok'  ELSE 'no' END   
 
  WHEN 1 THEN -- OR Condition      
    CASE      
    WHEN      
	  ( @AllComments1 IS NULL  OR        
       DT.Comment  Like '%'+@AllComments1+'%'  OR        
       ALT.Comment Like '%'+@AllComments1+'%'  OR        
       FT.Comment  Like '%'+@AllComments1+'%' )       
     OR       
          ( --@AllComments2 IS NULL  OR       
       DT.Comment  Like '%'+@AllComments2+'%'  OR       
       ALT.Comment Like '%'+@AllComments2+'%'  OR       
       FT.Comment  Like '%'+@AllComments2+'%' )         
    THEN 'ok'  ELSE 'no' END           
 END  =  'ok'          
      
 
-------- Select Rows include Cooments and All critia -------------------      
 
   SELECT siFiles INTO #TEMP FROM #TEMP2         
       WHERE siFiles in (SELECT siFiles FROM #TEMP1)        
 
-------- Select Dataset  --------------------------------------------          
 
   SELECT TOP (ISNULL( (select Top 1 TopSelect From MachineTable Where SI = @SI) ,1000000000)) --Percent 
     FT.siFiles,FileID,FName,LName,Phone1,Phone2,PaidAfter,BirthYear,ReferDate,Subject,                  
     thumb,FT.Comment,Address,Age,Job,RefFileID,DoctorName,ALT.SurgDate,SendType,              
     'SendTypeName'=CASE SendType WHEN 0 THEN 'اورژانس' ELSE 'عادي' END ,      
     'BEF_AFT'=CASE BEF_AFT WHEN 0 THEN 'Bef' ELSE 'Aft' END ,      
     'AllName' = LTrim(RTrim( LName +' '+ ISNULL(FName,'') ))  ,  
     'PaidAfterStatus'= Case PaidAfter when 0 then NULL else 'پرداخت شد' end,
	 Is3D,CASE Is3d When 0 then NULL else '3D' end Is3DTitle         
   From FilesTable FT                         
   INNER JOIN #TEMP T ON FT.siFiles = T.siFiles           
   LEFT JOIN AlbumTable ALT  ON ALT.siFiles = FT.siFiles      
   ORDER BY ReferDate DESC,  FT.siFiles DESC
 
 
-------- Drop All Temp Tables  ----------------------------------------      
 
   DROP TABLE #TEMP             
   DROP TABLE #TEMP1            
   DROP TABLE #TEMP2    
END;  
 
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_PageTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_PageTable] AS 
 Select  
	siPage,CheckCount,TitlePage,PagePhoto
 From PageTable
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_PageTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

Create Proc [dbo].[USP_Select_PageTable_BySerial](@siPage int) AS 
 Select  
	siPage,CheckCount,TitlePage,PagePhoto
 From PageTable
 Where siPage= @siPage



GO

/****** Object:  StoredProcedure [dbo].[USP_SELECT_PatientInChecking]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROC [dbo].[USP_SELECT_PatientInChecking](@MachineCheck nvarchar(100),@siWait int ) AS
BEGIN
	-- Status  = 1 -- در حالت ثبت شده باید چک شود
	SELECT 1 as ErrorNO, siWait, siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, Status, Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
	FROM WaitTable -- همین پرونده جاری
	WHERE MachineCheck = @MachineCheck and siWait = @siWait and Status = 1 and MachineCheck IS NOT NULL
 
	UNION
 
	SELECT 3 as ErrorNO, siWait, siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, Status, Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
	FROM WaitTable  -- یک پرونده دیگر توسط خودم باز مانده است
	WHERE MachineCheck = @MachineCheck and siWait <> @siWait and Status = 1 and MachineCheck IS NOT NULL
 
	UNION
 
	SELECT 2 as ErrorNO, siWait, siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, Status, Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
	FROM WaitTable -- توسط دیگری باز شده است
	WHERE MachineCheck <> @MachineCheck and siWait = @siWait and Status = 1 and MachineCheck IS NOT NULL
 
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_SELECT_PatientInPhotography]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SELECT_PatientInPhotography](@MachinePhoto nvarchar(100),@siWait int ) AS
BEGIN
	DECLARE @Status int = 2
	SELECT 1 as ErrorNO, siWait, WT.siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, WT.Status, WT.Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
 	FROM WaitTable WT-- همین پرونده جاری
	LEFT JOIN Wait3DTable W3 ON WT.siFiles = W3.siFiles
 	WHERE MachinePhoto = @MachinePhoto and siWait = @siWait and WT.Status = @Status and MachinePhoto IS NOT NULL and W3.TakePhoto IS NULL 

 
	UNION
 
	SELECT 3 as ErrorNO, siWait, WT.siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, WT.Status, WT.Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
	FROM WaitTable  WT-- یک پرونده دیگر توسط خودم باز مانده است
	LEFT JOIN Wait3DTable W3 ON WT.siFiles = W3.siFiles
	WHERE MachinePhoto = @MachinePhoto and siWait <> @siWait and WT.Status = @Status and MachinePhoto IS NOT NULL and W3.TakePhoto IS NULL
 


	UNION
 
	SELECT 2 as ErrorNO, siWait, WT.siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, WT.Status, WT.Comment, WaitCall, WaitPhoto, WaitService, MachinePhoto
	FROM WaitTable WT-- توسط دیگری باز شده است
	LEFT JOIN Wait3DTable W3 ON WT.siFiles = W3.siFiles
	WHERE MachinePhoto <> @MachinePhoto and siWait = @siWait and WT.Status = @Status and MachinePhoto IS NOT NULL and W3.TakePhoto IS NULL

 
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Patients]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Patients](@FileId varchar(15) ,@FName varchar(50) ,@LName varchar(50) ,@Phone1 varchar(15) , @Age varchar(5) ,@ReferDate varchar(10) ,@Subject varchar(100)) AS
BEGIN
	SELECT siFiles, FT.FileId, FT.FName, FT.LName, Phone1, Phone2, Age, ReferDate, DoctorName, Subject, MedicalID 
	FROM FilesTable FT
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor 
	WHERE 
		(@FileId IS NULL OR FT.FileId Like '%'+@FileId+'%') And 
		(@FName IS NULL OR  FT.FName Like '%'+@FName+'%') And 
		(@LName IS NULL OR  FT.LName Like '%'+@LName+'%') And 
		(@Phone1 IS NULL OR  Phone1 Like '%'+@Phone1+'%') And 
		(@Age IS NULL OR  Age Like '%'+@Age+'%') And 
		(@ReferDate IS NULL OR  ReferDate Like '%'+@ReferDate+'%') And 
		(@Subject IS NULL OR  Subject Like '%'+@Subject+'%')  
	order by ReferDate desc
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_PrivateTarrif_BysiDoctor]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_Select_PrivateTarrif_BysiDoctor](@siDoctors int) AS 
BEGIN
	SELECT 
		siPrivateTariff, PT.siDoctors, 
 		FileID, FName, LName, Job, Address1, Address2, PerDiscount, SumAfter
 	FROM PrivateTariffTable PT
	INNER JOIN   DoctorsTable DT  ON   PT.siDoctors = DT.siDoctors
	WHERE PT.siDoctors = @siDoctors	
	
END






GO

/****** Object:  StoredProcedure [dbo].[USP_Select_PSD_ByDoctor]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_PSD_ByDoctor]( @siDoctors int ) AS 
BEGIN
	SELECT 
		PS.siDoctors,
		PS.Doctor,
		PS.PSDFile1, PS.HasName1,
		PS.PSDFile2, PS.HasName2, 
		PS.PSDFileAfter1, 
		PS.HasNameAfter1,
		PS.PSDFileAfter2, 
		PS.HasNameAfter2
		,(Select PSDPath from ConfigTable) as PSDPath
	FROM PSDTable PS
	WHERE siDoctors =@siDoctors 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_PSD_ByPatient]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_PSD_ByPatient]( @siFiles int ) AS 
BEGIN
	SELECT 
		FT.FileID, 
		FT.FName, 
		FT.LName, 
		FT.PathFolder,
		FT.ReferDate, 
		FT.Bef_Aft,
		FT.BirthYear,
		ALT.AssurList, 
		'Path'= FT.PathFolder+'\'+
				Dc.FolderName+'\'+
				FT.LName+' '+
				FT.FName+' '+ 
				CAST(FT.FileId AS NVARCHAR(200)),
		'PathFinal'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Final',
		'PathEMail'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-EMail',
		'PathOriginal'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Original',
		'PathOther'=FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200))+
					'-Others',
		PS.siDoctors,
		PS.Doctor,
		PS.PSDFile1, 
		ISNULL(PS.HasName1,'0') as HasName1 ,
		PS.PSDFile2, 
		ISNULL(PS.HasName2,'0') as HasName2, 
		PS.PSDFileAfter1, 
		ISNULL(PS.HasNameAfter1,'0') as HasNameAfter1, 
		PS.PSDFileAfter2, 
		ISNULL(PS.HasNameAfter2,'0') as HasNameAfter2, 
		(Select TOP 1 PSDPath from ConfigTable) as PSDPath
		 
	FROM FilesTable FT
	INNER JOIN  AlbumTable		ALT ON FT.siFiles = ALT.siFiles
	INNER JOIN  DoctorsTable	DC  ON Ft.siDoctor = DC.siDoctors 
	INNER JOIN  PSDTable		PS	ON DC.siDoctors = PS.siDoctors 
	WHERE FT.siFiles =   @siFiles
END;

GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ReceiptTable_Full]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_ReceiptTable_Full]( @TopCategory varchar(500), @SubCategory int )  AS
BEGIN
	SELECT DISTINCT TOP 10000  
		siReceipt,Title,siReceipt2,SeqNo
	FROM ReceiptLinkTable RLT
	INNER JOIN ReceiptTable RT On RT.siReceipt = RLT.siReceipt3
	WHERE ( @SubCategory=0 OR siReceipt2 = @SubCategory)
			And (PATINDEX('%,'+CAST(siReceipt1 as varchar(5))+',%', ','+@TopCategory+',')>0 )
	ORDER BY siReceipt2,SeqNo,siReceipt
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ReceiptTable_Root]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [dbo].[USP_Select_ReceiptTable_Root]  AS
BEGIN
  SELECT siReceipt, Title, Category
  FROM ReceiptTable
  WHERE  Category =1
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ReferenceList]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_ReferenceList]( @siFiles int ) AS
--declare  @siFiles int = 69941;
 
	SELECT TOP 10000000
			CatLevel, TopCat, SubCat1 ,SubCat2,
			LEAD( SubCat1 ) OVER( partition by CatLevel,SubCat1 order by SubCat1,SubCat2) Edge,
			-1+DENSE_RANK() OVER( ORDER BY  SubCat1) GrpSubCat,
			CAT.Title as CatTitle, 
			SUB2.Title as CheckerTitle ,SUB2.PhotoTitle as PhotoTitle, SUB2.EditorTitle as EditorTitle , 
			Comment1, Comment2
	INTO #TEMP
	FROM
		(
			SELECT 
				0 CatLevel,TopCat.value('F[1]','Varchar(100)') TopCat, 0 SubCat1, 0 SubCat2 , Comment1, Comment2
			FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
			CROSS APPLY A.TopCategory.nodes('T') Tbl(TopCat)
			WHERE siFiles= @siFiles
			UNION ALL
			SELECT 
				1,0, SubCat1.value('F[1]','Varchar(100)') , SubCat1.value('F[2]','Varchar(100)'), Comment1, Comment2 
			FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
			CROSS APPLY A.SubCategory1.nodes('T') Tbl(SubCat1)
			WHERE siFiles= @siFiles
			UNION ALL
			SELECT 
				2,0, SubCat2.value('F[1]','Varchar(100)') , SubCat2.value('F[2]','Varchar(100)'), Comment1, Comment2 
			FROM (SELECT siFileReceipt, siFiles, CAST(TopCategory as XML) TopCategory,CAST( SubCategory1 as XML) SubCategory1,CAST( SubCategory2 as XML) SubCategory2, Comment1, Comment2 FROM FileReceiptTable) A
			CROSS APPLY A.SubCategory2.nodes('T') Tbl(SubCat2)
			WHERE siFiles= @siFiles
 
		)TBL(CatLevel,TopCat,SubCat1,SubCat2, Comment1, Comment2)
		LEFT JOIN ReceiptTable CAT  ON  CAT.siReceipt = TBL.TopCat 
		LEFT JOIN ReceiptTable SUB1 ON SUB1.siReceipt = TBL.SubCat1 
		LEFT JOIN ReceiptTable SUB2 ON SUB2.siReceipt = TBL.SubCat2 
 		--ORDER BY 1,2,3,4
 		ORDER BY 1,case When SubCat1 >= 207 then NULL else 2 end,3,4


	--Select * FROM #TEMP;
	--DROP TABLE #TEMP ;
	--return
 
	DECLARE @CatTitle nvarchar(4000) ='',
			@PhotoSub1 nvarchar(4000) ='', @EditorSub1 nvarchar(4000) ='', @CheckerSub1 nvarchar(4000) ='',
			@PhotoSub2 nvarchar(4000) ='', @EditorSub2 nvarchar(4000) ='', @CheckerSub2 nvarchar(4000) ='' ,
			@BackColor nvarchar(4000) ='',	@LifeSize nvarchar(4000) ='',	@GridLine nvarchar(4000) ='',
			@Comment1 nvarchar(4000) ='',	@Comment2 nvarchar(4000) ='' 
 
	--------------------------------------------------------------------------------
 
	SELECT 
		@BackColor = CASE ISNULL(BackColor,4) 
						WHEN 0 THEN N'آبی' 
						WHEN 1 THEN N'مشکی'
						WHEN 2 THEN N'سفید'
						WHEN 3 THEN N'سرمه ای' END, 
 
		@LifeSize = CASE ISNULL(LifeSize,0) 
						WHEN 1 THEN ' LifeSize' ELSE '' 	END,
 
		@GridLine = CASE ISNULL(GridLine,0) 
						WHEN 1 THEN ' GridLine' ELSE '' 	END
 
	FROM FileReceiptTable 
	WHERE siFiles= @siFiles
 
	--------------------------------------------------------------------------------
 
	SELECT 
		@CatTitle =  CASE @CatTitle WHEN '' THEN '' ELSE @CatTitle+ ' -- ' END +CatTitle
	FROM #TEMP
	Where CatLevel = 0;
			
	--------------------------------------------------------------------------------
 
	SELECT 
		@CheckerSub1 =  @CheckerSub1 +CASE WHEN @CheckerSub1 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,CheckerTitle),
		@PhotoSub1 =  @PhotoSub1 +CASE WHEN @PhotoSub1 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,PhotoTitle),
		@EditorSub1 =  @EditorSub1 +CASE WHEN @EditorSub1 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,EditorTitle)
		--@PhotoSub1   =  @PhotoSub1   +CASE WHEN @PhotoSub1 =''   THEN '' ELSE CHAR(13) END+ CASE ISNULL(Edge,0) WHEN 0 THEN  CHAR(13) ELSE '' END+PhotoTitle,
		--@EditorSub1  =  @EditorSub1  +CASE WHEN @EditorSub1 =''  THEN '' ELSE CHAR(13) END+ CASE ISNULL(Edge,0) WHEN 0 THEN  CHAR(13) ELSE '' END+EditorTitle 
	FROM #TEMP
	Where CatLevel = 1;
 
	--------------------------------------------------------------------------------
 
	SELECT 
		@CheckerSub2 =  @CheckerSub2 +CASE WHEN @CheckerSub2 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,CheckerTitle),
		@PhotoSub2 =  @PhotoSub2 +CASE WHEN @PhotoSub2 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,PhotoTitle),
		@EditorSub2 =  @EditorSub2 +CASE WHEN @EditorSub2 ='' THEN '' ELSE CHAR(13) END+CONCAT( SubCat1,EditorTitle)
		--@PhotoSub2   = @PhotoSub2   +CHAR(13)+CASE ISNULL(Edge,0) WHEN 0 THEN  CHAR(13) ELSE '' END + PhotoTitle,
		--@EditorSub2  = @EditorSub2  +CHAR(13)+CASE ISNULL(Edge,0) WHEN 0 THEN  CHAR(13) ELSE '' END + EditorTitle 
	FROM #TEMP
	Where CatLevel = 2;
 
	--------------------------------------------------------------------------------
 
	SELECT DISTINCT
		@Comment1  = ISNULL(Comment1,''),	@Comment2 = ISNULL(Comment2,'')
	FROM #TEMP
	
	Select	
		@BackColor   as BackColor ,
		@LifeSize    as  LifeSize ,
		@GridLine    as GridLine,
		@CatTitle    as CatTitle  ,
		@PhotoSub1   as PhotoSub1, 
		@PhotoSub2   as PhotoSub2 ,
		@EditorSub1  as EditorSub1, 
		@EditorSub2  as EditorSub2,
		@CheckerSub1 as CheckerSub1, 
		@CheckerSub2 as CheckerSub2,
		@Comment1    as Comment1 ,
		@Comment2    as Comment2 
 
 
	DROP TABLE #TEMP ;
 
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

CREATE Proc [dbo].[USP_Select_ServiceTable] AS 
Begin
 Select  
	siServiceTable,siFiles,siWait,siCommonTariff,Number,Type
 From ServiceTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable_By_siAccountUsed]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_ServiceTable_By_siAccountUsed](@siAccount  int) AS       
Begin       
 Select        
 siExtraServiceTable, siAccount, siCommonTariff, FactorDate, 
 Number, Type, UsedTariffName, UsedPrice,
 'Fee'=UsedPrice*Number    
 From ExtraServiceTable ST    
 Where siAccount= @siAccount     
End    
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable_By_siFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Select_ServiceTable_By_siFiles](@siFiles  int) AS   
Begin   
 Select    
 siServiceTable,siFiles,siWait,ST.siCommonTariff,Number,ST.Type,
 CT.IsAfter,CT.TariffName,Price,'Fee'=Price*Number
 From ServiceTable ST
 INNER JOIN CommonTariffTable CT ON CT.siCommonTariff = ST.siCommonTariff
 Where siFiles= @siFiles 
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable_By_siFilesUsed]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Select_ServiceTable_By_siFilesUsed](@siFiles  int) AS     
Begin     
 Select      
 siServiceTable,siFiles,siWait,ST.siCommonTariff,Number,
 ST.Type as IsAfter,UsedTariffName as TariffName,UsedPrice as Price,
 'Fee'=UsedPrice*Number  
 From ServiceTable ST  
 Where siFiles= @siFiles   
End  
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable_By_siWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Select_ServiceTable_By_siWait]( @siWait  int) AS 
Begin 
 Select  
	siServiceTable,siFiles,siWait,siCommonTariff,Number,Type
 From ServiceTable
 Where siWait= @siWait
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_ServiceTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

CREATE Proc [dbo].[USP_Select_ServiceTable_BySerial](@siServiceTable  int) AS 
Begin 
 Select  
	siServiceTable,siFiles,siWait,siCommonTariff,Number,Type
 From ServiceTable
 Where siServiceTable= @siServiceTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Statistic_PIVOT]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Statistic_PIVOT](  
@Today   varchar(10) ,  
@Zone1   varchar(10) ,@Zone2   varchar(10) ,@Zone3   varchar(10) ,@Zone4   varchar(10) ,@Zone5   varchar(10) ,@Zone6   varchar(10) ,  
@Zone7   varchar(10) ,@Zone8   varchar(10) ,@Zone9   varchar(10) ,@Zone10  varchar(10) ,@Zone11  varchar(10) ,@Zone12  varchar(10) ,  
@Zone13  varchar(10) ,@Zone14  varchar(10) ,@Zone15  varchar(10) ,@Zone16  varchar(10) ,@Zone17  varchar(10) ,@Zone18  varchar(10) ,  
@Zone19  varchar(10) ,@Zone20  varchar(20) ,@Zone21  varchar(10) ,@Zone22  varchar(10) ,@Zone23  varchar(10) ,@Zone24  varchar(10) ,
@siDoctor  int =NULL  
) AS  
/*Declare   
@Today   varchar(10) = '1394/07/30',  
@Zone1   varchar(10) = '1394/07/01',   @Zone2   varchar(10) = '1394/06/01',   @Zone3   varchar(10) = '1394/05/01',  
@Zone4   varchar(10) = '1394/04/01',   @Zone5   varchar(10) = '1394/03/01',   @Zone6   varchar(10) = '1394/02/01',  
@Zone7   varchar(10) = '1394/01/01',   @Zone8   varchar(10) = '1393/12/01',   @Zone9   varchar(10) = '1393/11/01',  
@Zone10  varchar(10) = '1393/10/01',   @Zone11  varchar(10) = '1393/09/01',   @Zone12  varchar(10) = '1393/08/01',
@Zone13  varchar(10) = '1393/07/01',   @Zone14  varchar(10) = '1393/06/01',   @Zone15  varchar(10) = '1393/05/01',
@Zone16  varchar(10) = '1393/04/01',   @Zone17  varchar(10) = '1393/03/01',   @Zone18  varchar(10) = '1393/02/01',
@Zone19  varchar(10) = '1393/01/01',   @Zone20  varchar(10) = '1392/12/01',   @Zone21  varchar(10) = '1392/11/01',
@Zone22  varchar(10) = '1392/10/01',   @Zone23  varchar(10) = '1392/09/01',   @Zone24  varchar(10) = '1392/08/01',
@siDoctor int = NULL
*/  
	SELECT 
		RET.siDoctor, ISNULL( DT.LName ,'')+'    '+ISNULL(DT.FName,'') as DoctorName, DT.Job, siHospital,FullName,DT.IsTebDoc, 
		Zone1,Zone2,Zone3,Zone4,Zone5,Zone6,Zone7,Zone8,Zone9,Zone10,Zone11,Zone12,Zone13, 
		Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 
	FROM(  
		SELECT 
			siDoctor,  siHospital,FullName, 
			Zone1,Zone2,Zone3,Zone4,Zone5,Zone6,Zone7,Zone8,Zone9,Zone10,Zone11,Zone12,Zone13, 
			Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 
		FROM(  
			SELECT   
				siDoctor, siHospital,FullName, L, Count(L) as P_Count 
			FROM(  
				SELECT   
					siDoctor, HT.siHospital,HT.FullName,   
					'L'=  
					CASE    
					WHEN ReferDate >= @Zone1   and ReferDate <= @Today   then 'Zone1'  
					WHEN ReferDate >= @Zone2   and ReferDate <  @Zone1   then 'Zone2'  
					WHEN ReferDate >= @Zone3   and ReferDate <  @Zone2   then 'Zone3'  
					WHEN ReferDate >= @Zone4   and ReferDate <  @Zone3   then 'Zone4'  
					WHEN ReferDate >= @Zone5   and ReferDate <  @Zone4   then 'Zone5'  
					WHEN ReferDate >= @Zone6   and ReferDate <  @Zone5   then 'Zone6'  
					WHEN ReferDate >= @Zone7   and ReferDate <  @Zone6   then 'Zone7'  
					WHEN ReferDate >= @Zone8   and ReferDate <  @Zone7   then 'Zone8'  
					WHEN ReferDate >= @Zone9   and ReferDate <  @Zone8   then 'Zone9'  
					WHEN ReferDate >= @Zone10  and ReferDate <  @Zone9   then 'Zone10'  
					WHEN ReferDate >= @Zone11  and ReferDate <  @Zone10  then 'Zone11'  
					WHEN ReferDate >= @Zone12  and ReferDate <  @Zone11  then 'Zone12'  
					WHEN ReferDate >= @Zone13  and ReferDate <  @Zone12  then 'Zone13'  
					WHEN ReferDate >= @Zone14  and ReferDate <  @Zone13  then 'Zone14'  
					WHEN ReferDate >= @Zone15  and ReferDate <  @Zone14  then 'Zone15'  
					WHEN ReferDate >= @Zone16  and ReferDate <  @Zone15  then 'Zone16'  
					WHEN ReferDate >= @Zone17  and ReferDate <  @Zone16  then 'Zone17'  
					WHEN ReferDate >= @Zone18  and ReferDate <  @Zone17  then 'Zone18'  
					WHEN ReferDate >= @Zone19  and ReferDate <  @Zone18  then 'Zone19'  
					WHEN ReferDate >= @Zone20  and ReferDate <  @Zone19  then 'Zone20'  
					WHEN ReferDate >= @Zone21  and ReferDate <  @Zone20  then 'Zone21'  
					WHEN ReferDate >= @Zone22  and ReferDate <  @Zone21  then 'Zone22'  
					WHEN ReferDate >= @Zone23  and ReferDate <  @Zone22  then 'Zone23'  
					WHEN ReferDate >= @Zone24  and ReferDate <  @Zone23  then 'Zone24'  
					END   
				FROM 
				(
				SELECT siDoctor,siHospital,ReferDate FROM FilesTable F 
				) FT
				INNER JOIN HospitalTable HT ON FT.siHospital = HT.siHospital
				Where @siDoctor IS NULL Or siDoctor = @siDoctor
			)  A   
			GROUP BY siDoctor, siHospital,FullName, L  
		) SourceTable  
		PIVOT  
		(  
		SUM(P_Count)  
		FOR L IN (  
			Zone1 , Zone2 , Zone3 , Zone4 , Zone5 , Zone6 ,  Zone7 , Zone8 , Zone9 , Zone10, Zone11, Zone12,
			Zone13, Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 )  
		) AS PivotTable  
  
	) RET 
	INNER JOIN DoctorsTable DT ON DT.siDoctors = RET.siDoctor 
 
	ORDER BY DoctorName, siHospital 
 
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Statistic_PIVOT_OLD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Statistic_PIVOT_OLD]
(  
@Today   varchar(10) ,  
@Zone1   varchar(10) ,@Zone2   varchar(10) ,@Zone3   varchar(10) ,@Zone4   varchar(10) ,@Zone5   varchar(10) ,@Zone6   varchar(10) ,  
@Zone7   varchar(10) ,@Zone8   varchar(10) ,@Zone9   varchar(10) ,@Zone10  varchar(10) ,@Zone11  varchar(10) ,@Zone12  varchar(10) ,  
@Zone13  varchar(10) ,@Zone14  varchar(10) ,@Zone15  varchar(10) ,@Zone16  varchar(10) ,@Zone17  varchar(10) ,@Zone18  varchar(10) ,  
@Zone19  varchar(10) ,@Zone20  varchar(20) ,@Zone21  varchar(10) ,@Zone22  varchar(10) ,@Zone23  varchar(10) ,@Zone24  varchar(10) ,
@siDoctor  int =NULL  
) AS  
/*Declare   
@Today   varchar(10) = '1394/07/30',  
@Zone1   varchar(10) = '1394/07/01',   @Zone2   varchar(10) = '1394/06/01',   @Zone3   varchar(10) = '1394/05/01',  
@Zone4   varchar(10) = '1394/04/01',   @Zone5   varchar(10) = '1394/03/01',   @Zone6   varchar(10) = '1394/02/01',  
@Zone7   varchar(10) = '1394/01/01',   @Zone8   varchar(10) = '1393/12/01',   @Zone9   varchar(10) = '1393/11/01',  
@Zone10  varchar(10) = '1393/10/01',   @Zone11  varchar(10) = '1393/09/01',   @Zone12  varchar(10) = '1393/08/01',
@Zone13  varchar(10) = '1393/07/01',   @Zone14  varchar(10) = '1393/06/01',   @Zone15  varchar(10) = '1393/05/01',
@Zone16  varchar(10) = '1393/04/01',   @Zone17  varchar(10) = '1393/03/01',   @Zone18  varchar(10) = '1393/02/01',
@Zone19  varchar(10) = '1393/01/01',   @Zone20  varchar(10) = '1392/12/01',   @Zone21  varchar(10) = '1392/11/01',
@Zone22  varchar(10) = '1392/10/01',   @Zone23  varchar(10) = '1392/09/01',   @Zone24  varchar(10) = '1392/08/01',
@siDoctor int = NULL
*/  
	DECLARE @siHospital int
	Select top 1 @siHospital=siHospital From HospitalTable Where Location = 1 
	--Print @Today
	--Print @Zone24
	SELECT 
		RET.siDoctor, ISNULL( DT.LName ,'')+'    '+ISNULL(DT.FName,'') as DoctorName, DT.Job, siHospital,FullName,DT.IsTebDoc,
		Zone1,Zone2,Zone3,Zone4,Zone5,Zone6,Zone7,Zone8,Zone9,Zone10,Zone11,Zone12,Zone13, 
		Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 
	FROM(  
		SELECT 
			siDoctor,  siHospital,FullName, 
			Zone1,Zone2,Zone3,Zone4,Zone5,Zone6,Zone7,Zone8,Zone9,Zone10,Zone11,Zone12,Zone13, 
			Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 
		FROM(  
			SELECT   
				siDoctor, siHospital,FullName, L, Count(L) as P_Count 
			FROM(  
				SELECT   
					siDoctor, HT.siHospital,HT.FullName,   
					'L'=  
					CASE    
					WHEN TebLab =1 and ReferDate >= @Zone1   and ReferDate <= @Today   then 'Zone1'  
					WHEN TebLab =1 and ReferDate >= @Zone2   and ReferDate <  @Zone1   then 'Zone2'  
					WHEN TebLab =1 and ReferDate >= @Zone3   and ReferDate <  @Zone2   then 'Zone3'  
					WHEN TebLab =1 and ReferDate >= @Zone4   and ReferDate <  @Zone3   then 'Zone4'  
					WHEN TebLab =1 and ReferDate >= @Zone5   and ReferDate <  @Zone4   then 'Zone5'  
					WHEN TebLab =1 and ReferDate >= @Zone6   and ReferDate <  @Zone5   then 'Zone6'  
					WHEN TebLab =1 and ReferDate >= @Zone7   and ReferDate <  @Zone6   then 'Zone7'  
					WHEN TebLab =1 and ReferDate >= @Zone8   and ReferDate <  @Zone7   then 'Zone8'  
					WHEN TebLab =1 and ReferDate >= @Zone9   and ReferDate <  @Zone8   then 'Zone9'  
					WHEN TebLab =1 and ReferDate >= @Zone10  and ReferDate <  @Zone9   then 'Zone10'  
					WHEN TebLab =1 and ReferDate >= @Zone11  and ReferDate <  @Zone10  then 'Zone11'  
					WHEN TebLab =1 and ReferDate >= @Zone12  and ReferDate <  @Zone11  then 'Zone12'  
					WHEN TebLab =1 and ReferDate >= @Zone13  and ReferDate <  @Zone12  then 'Zone13'  
					WHEN TebLab =1 and ReferDate >= @Zone14  and ReferDate <  @Zone13  then 'Zone14'  
					WHEN TebLab =1 and ReferDate >= @Zone15  and ReferDate <  @Zone14  then 'Zone15'  
					WHEN TebLab =1 and ReferDate >= @Zone16  and ReferDate <  @Zone15  then 'Zone16'  
					WHEN TebLab =1 and ReferDate >= @Zone17  and ReferDate <  @Zone16  then 'Zone17'  
					WHEN TebLab =1 and ReferDate >= @Zone18  and ReferDate <  @Zone17  then 'Zone18'  
					WHEN TebLab =1 and ReferDate >= @Zone19  and ReferDate <  @Zone18  then 'Zone19'  
					WHEN TebLab =1 and ReferDate >= @Zone20  and ReferDate <  @Zone19  then 'Zone20'  
					WHEN TebLab =1 and ReferDate >= @Zone21  and ReferDate <  @Zone20  then 'Zone21'  
					WHEN TebLab =1 and ReferDate >= @Zone22  and ReferDate <  @Zone21  then 'Zone22'  
					WHEN TebLab =1 and ReferDate >= @Zone23  and ReferDate <  @Zone22  then 'Zone23'  
					WHEN TebLab =1 and ReferDate >= @Zone24  and ReferDate <  @Zone23  then 'Zone24' 
					END   
				FROM 
				(
				SELECT siDoctor,siHospital,ReferDate, 1 as TebLab FROM FilesTable 
				WHERE ReferDate BETWEEN @Zone24 AND @ToDay 
				/*UNION
				SELECT siDoctor,@siHospital as siHospital,fAcceptionDate as ReferDate, 2 as TebLab FROM 
				(
					SELECT 
						T.siDoctor, AutoStatus,fAcceptionDate
					FROM NovinAcceptation A
					LEFT JOIN NovinDoctor B ON A.fCodeDoctor = B.fCode
					LEFT JOIN NovinSpecialty DS ON B.fCodeDoctorSpecialty = DS.fCode
					LEFT JOIN NovinTebnegarPatients T On T.fCode = A.fCode AND T.RegisterDate IS NOT NULL
					WHERE 
						fAcceptionDate BETWEEN @Zone24 AND @ToDay AND A.fCancellation <> 1
				) K
				WHERE AutoStatus in (1,2) 
				*/ 
				) FT
				INNER JOIN HospitalTable HT ON FT.siHospital = HT.siHospital
				Where @siDoctor IS NULL Or siDoctor = @siDoctor
			)  A   
			GROUP BY siDoctor, siHospital,FullName, L  
		) SourceTable  
		PIVOT  
		(  
		SUM(P_Count)  
		FOR L IN (  
			Zone1 , Zone2 , Zone3 , Zone4 , Zone5 , Zone6 ,  Zone7 , Zone8 , Zone9 , Zone10, Zone11, Zone12,
			Zone13, Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 )  
		) AS PivotTable  
  
	) RET 
	INNER JOIN DoctorsTable DT ON DT.siDoctors = RET.siDoctor 
 
	ORDER BY DoctorName, siHospital 
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Statistic_PIVOT2]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Statistic_PIVOT2](  
 @Today   varchar(10) ,  
 @Zone1   varchar(10) ,@Zone2   varchar(10) ,@Zone3   varchar(10) ,@Zone4   varchar(10) ,@Zone5   varchar(10) ,@Zone6   varchar(10) ,  
 @Zone7   varchar(10) ,@Zone8   varchar(10) ,@Zone9   varchar(10) ,@Zone10  varchar(10) ,@Zone11  varchar(10) ,@Zone12  varchar(10) ,  
 @Zone13  varchar(10) ,@Zone14  varchar(10) ,@Zone15  varchar(10) ,@Zone16  varchar(10) ,@Zone17  varchar(10) ,@Zone18  varchar(10) ,  
 @Zone19  varchar(10) ,@Zone20  varchar(20) ,@Zone21  varchar(10) ,@Zone22  varchar(10) ,@Zone23  varchar(10) ,@Zone24  varchar(10) ,
 @siDoctor  int =NULL , @Mode int =0
) AS
BEGIN
/*	DECLARE   
		@Today   varchar(10) = '1394/07/30',  
		@Zone1   varchar(10) = '1394/07/01',   @Zone2   varchar(10) = '1394/06/01',   @Zone3   varchar(10) = '1394/05/01',  
		@Zone4   varchar(10) = '1394/04/01',   @Zone5   varchar(10) = '1394/03/01',   @Zone6   varchar(10) = '1394/02/01',  
		@Zone7   varchar(10) = '1394/01/01',   @Zone8   varchar(10) = '1393/12/01',   @Zone9   varchar(10) = '1393/11/01',  
		@Zone10  varchar(10) = '1393/10/01',   @Zone11  varchar(10) = '1393/09/01',   @Zone12  varchar(10) = '1393/08/01',
		@Zone13  varchar(10) = '1393/07/01',   @Zone14  varchar(10) = '1393/06/01',   @Zone15  varchar(10) = '1393/05/01',
		@Zone16  varchar(10) = '1393/04/01',   @Zone17  varchar(10) = '1393/03/01',   @Zone18  varchar(10) = '1393/02/01',
		@Zone19  varchar(10) = '1393/01/01',   @Zone20  varchar(10) = '1392/12/01',   @Zone21  varchar(10) = '1392/11/01',
		@Zone22  varchar(10) = '1392/10/01',   @Zone23  varchar(10) = '1392/09/01',   @Zone24  varchar(10) = '1392/08/01',
		@siDoctor int = NULL
*/
	DROP TABLE IF EXISTS #Temp
	 
	SELECT siDoctor,siHospital, Z
	INTO #Temp
	FROM(    
		SELECT	
		siDoctor,IIF(@Mode=0, NULL,siHospital) as siHospital,   
		'Z'=  
		CASE    
			WHEN ReferDate >= @Zone1   and ReferDate <= @Today   then 'Zone1'  
			WHEN ReferDate >= @Zone2   and ReferDate <  @Zone1   then 'Zone2'  
			WHEN ReferDate >= @Zone3   and ReferDate <  @Zone2   then 'Zone3'  
			WHEN ReferDate >= @Zone4   and ReferDate <  @Zone3   then 'Zone4'  
			WHEN ReferDate >= @Zone5   and ReferDate <  @Zone4   then 'Zone5'  
			WHEN ReferDate >= @Zone6   and ReferDate <  @Zone5   then 'Zone6'  
			WHEN ReferDate >= @Zone7   and ReferDate <  @Zone6   then 'Zone7'  
			WHEN ReferDate >= @Zone8   and ReferDate <  @Zone7   then 'Zone8'  
			WHEN ReferDate >= @Zone9   and ReferDate <  @Zone8   then 'Zone9'  
			WHEN ReferDate >= @Zone10  and ReferDate <  @Zone9   then 'Zone10'  
			WHEN ReferDate >= @Zone11  and ReferDate <  @Zone10  then 'Zone11'  
			WHEN ReferDate >= @Zone12  and ReferDate <  @Zone11  then 'Zone12'  
			WHEN ReferDate >= @Zone13  and ReferDate <  @Zone12  then 'Zone13'  
			WHEN ReferDate >= @Zone14  and ReferDate <  @Zone13  then 'Zone14'  
			WHEN ReferDate >= @Zone15  and ReferDate <  @Zone14  then 'Zone15'  
			WHEN ReferDate >= @Zone16  and ReferDate <  @Zone15  then 'Zone16'  
			WHEN ReferDate >= @Zone17  and ReferDate <  @Zone16  then 'Zone17'  
			WHEN ReferDate >= @Zone18  and ReferDate <  @Zone17  then 'Zone18'  
			WHEN ReferDate >= @Zone19  and ReferDate <  @Zone18  then 'Zone19'  
			WHEN ReferDate >= @Zone20  and ReferDate <  @Zone19  then 'Zone20'  
			WHEN ReferDate >= @Zone21  and ReferDate <  @Zone20  then 'Zone21'  
			WHEN ReferDate >= @Zone22  and ReferDate <  @Zone21  then 'Zone22'  
			WHEN ReferDate >= @Zone23  and ReferDate <  @Zone22  then 'Zone23'  
			WHEN ReferDate >= @Zone24  and ReferDate <  @Zone23  then 'Zone24'  
		END   	
	FROM FilesTable FT   
	WHERE @siDoctor IS NULL OR siDoctor = @siDoctor
	) A
	WHERE Z IS NOT NULL  	
	
	SELECT 
		siDoctor,
		ISNULL( DT.LName ,'')+'    '+ISNULL(DT.FName,'') as DoctorName, Job,PivotTable.siHospital,HT.FullName,
		Zone1,Zone2,Zone3,Zone4,Zone5,Zone6,Zone7,Zone8,Zone9,Zone10,Zone11,Zone12,Zone13,
		Zone14,Zone15,Zone16,Zone17,Zone18,Zone19,Zone20,Zone21,Zone22,Zone23,Zone24 
	FROM 
	(
		SELECT siDoctor, siHospital, Z, COUNT(*) as P_Count FROM #Temp GROUP BY siDoctor, siHospital, Z
	) AS Src
	PIVOT  
	(  
	  SUM(P_Count)  
	  FOR Z IN 
	  (  
		  Zone1 , Zone2 , Zone3 , Zone4 , Zone5 , Zone6 ,  Zone7 , Zone8 , Zone9 , Zone10, Zone11, Zone12,
		  Zone13, Zone14, Zone15, Zone16, Zone17, Zone18,  Zone19, Zone20, Zone21, Zone22, Zone23, Zone24 
	  )  
	) AS PivotTable
	INNER JOIN DoctorsTable DT ON DT.siDoctors = PivotTable.siDoctor
	LEFT  JOIN HospitalTable HT ON HT.siHospital = PivotTable.siHospital  
	ORDER BY DoctorName, PivotTable.siHospital 
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_SurgeryByAlbum]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









Create Proc [dbo].[USP_Select_SurgeryByAlbum](@siAlbum int ) AS  
select   
    ISNULL(siSurgery,0) siSurgery   
   from AlbumSurgTable  
 where siAlbum = @siAlbum










GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Tarrif_By_siFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_Select_Tarrif_By_siFile](@siFiles int) AS
BEGIN
	SELECT  
		siFiles, Location, FullName, ForceAfter, TarrifBeforeType, TarrifAfterType, 
		AmountBefore, AmountAfter, HasTarrif, PaidAfter, SendType, Bef_Aft, FileID, PreCost
	FROM VW_SELECT_All_Tarrif
	WHERE siFiles = @siFiles
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_SELECT_Tarrif_Price_By_siFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
CREATE PROC [dbo].[USP_SELECT_Tarrif_Price_By_siFile]( @siFiles as int ) AS
SELECT 
	'All'=(
		SELECT  SUM(Number*Price) 
		FROM ServiceTable ST
		Left join CommonTariffTable CTT ON  ST.siCommonTariff = CTT.siCommonTariff
		WHERE siFiles = @siFiles  and  Disabled IS NULL and CTT.Type =0 ),
	'Normal'=(
		SELECT  SUM(Number*Price) 
		FROM ServiceTable ST
		Left join CommonTariffTable CTT ON  ST.siCommonTariff = CTT.siCommonTariff
		WHERE siFiles = @siFiles  and  Disabled IS NULL and CTT.Type =0 and IsAfter =0),
	'After'=(
		SELECT  SUM(Number*Price) 
		FROM ServiceTable ST
		Left join CommonTariffTable CTT ON  ST.siCommonTariff = CTT.siCommonTariff
		WHERE siFiles = @siFiles  and  Disabled IS NULL and CTT.Type =0 and IsAfter =1),
	'Extra'=(
		SELECT SUM(Price) FROM CommonTariffTable WHERE Type =2 and  Disabled IS NULL),
	'T_F'=( 
		SELECT SUM(Price) FROM CommonTariffTable WHERE Type =1 and TebService = 0 and  Disabled IS NULL),
	'T_B'=( 
		SELECT SUM(Price) FROM CommonTariffTable WHERE Type =1 and TebService = 1 and  Disabled IS NULL),
	'T_A'=( 
		SELECT SUM(Price) FROM CommonTariffTable WHERE Type =1 and TebService = 2 and  Disabled IS NULL),
	'T_O'=( 
		SELECT SUM(Price) FROM CommonTariffTable WHERE Type =1 and TebService = 3 and  Disabled IS NULL)
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Telegram_Novin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Telegram_Novin]( @Date nvarchar(10), @Done int) AS
BEGIN
	--DECLARE @Date nvarchar(10)= '1397/04/19', @Done int=0;
	DECLARE @FromDate nvarchar(10);
	
	SELECT @FromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 TelegramDays from ConfigTable), MiladiDate) )
	FROM TblDate A 
	WHERE A.Shamsi = @Date 
	;WITH CTE AS
	(
	SELECT 
		TP.FileID, 
		TP.fCode, 
		TP.FName, 
		TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, AnswerDate, 
		cast(TP.fCode as nvarchar(15))  as fCodeMonth,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName, 
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,
		Status, TelegramStatus,
		TP.SendType,
		'SendStatus' = 
			CASE TP.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),TP.fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),TP.fCode,'.pdf'),	
		IIF(ISNULL(IsActiveEmailLab,0)=0,'','E') as IsActiveEmailLab,
		IIF(TD3.Shamsi is not null,CONCAT(Convert(varchar(5),SentEMailLabTime,114), ' - ', TD3.Shamsi ),'')  as SentLabDate
		, SentEMailLabTime
	FROM NovinTebnegarPatients TP
	INNER JOIN NovinAcceptation A ON TP.fCode = A.fCode 
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	LEFT JOIN TblDate TD3 ON TD3.Miladi = CAST( SentEMailLabTime as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		TP.fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	)	
	SELECT
		FileID,fCode,FName,LName,FullName,FullName2,Mobile,A.MiladiDate,SendDateS,SendTime,
		ReferDate,ReferTime,DoctorName,DoctorName2,Status,TelegramStatus,SendType,SendStatus,
		TelegStatusTitle,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork,fCodeMonth,
		CASE WHEN Status =3 THEN Concat(CAST( CONVERT( Time, AnswerDate, 111) as nvarchar(5)),' - ', D.Shamsi) ELSE NULL END as AnswerDate
		, SentLabDate, IsActiveEmailLab
		
	FROM CTE A
	LEFT JOIN TblDate D ON CAST(A.AnswerDate as DATE) = D.MiladiDate
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, Status desc,
		ReferDate DESC , SendType, ReferTime
		
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Telegram_Novin_OLD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Telegram_Novin_OLD]( @Date nvarchar(10), @Done int) AS
BEGIN
	--DECLARE @Date nvarchar(10)= '1397/04/19', @Done int=0;
	DECLARE @FromDate nvarchar(10);
	
	SELECT @FromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 TelegramDays from ConfigTable), MiladiDate) )
	FROM TblDate A 
	WHERE A.Shamsi = @Date 
	;WITH CTE AS
	(
	SELECT 
		TP.FileID, TP.fCode, TP.FName, TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, AnswerDate,
		cast(TP.fCode as nvarchar(15))  as fCodeMonth,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName,
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,		 
		Status, TelegramStatus,
		FT.SendType,
		'SendStatus' = 
			CASE FT.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),TP.fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),TP.fCode,'.pdf')	,
		IIF(ISNULL(IsActiveEmailLab,0)=0,'','E') as IsActiveEmailLab,
		IIF(TD3.Shamsi is not null,CONCAT(Convert(varchar(5),SentEMailLabTime,114), ' - ', TD3.Shamsi ),'')  as SentLabDate
		,SentEMailLabTime
	FROM NovinTebnegarPatients TP
	INNER JOIN NovinAcceptation A ON TP.fCode = A.fCode 
	INNER JOIN FilesTable FT ON FT.FileID = TP.FileID
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	LEFT JOIN TblDate TD3 ON TD3.Miladi = CAST( SentEMailLabTime as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		TP.fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	UNION
 
	SELECT 
		TP.FileID, 
		TP.fCode, 
		TP.FName, 
		TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, AnswerDate, 
		cast(TP.fCode as nvarchar(15))  as fCodeMonth,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName, 
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,
		Status, TelegramStatus,
		TP.SendType,
		'SendStatus' = 
			CASE TP.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),TP.fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),TP.fCode,'.pdf'),	
		IIF(ISNULL(IsActiveEmailLab,0)=0,'','E') as IsActiveEmailLab,
		IIF(TD3.Shamsi is not null,CONCAT(Convert(varchar(5),SentEMailLabTime,114), ' - ', TD3.Shamsi ),'')  as SentLabDate
		, SentEMailLabTime
	FROM NovinTebnegarPatients TP
	INNER JOIN NovinAcceptation A ON TP.fCode = A.fCode 
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	LEFT JOIN TblDate TD3 ON TD3.Miladi = CAST( SentEMailLabTime as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		TP.fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	)	
	SELECT
		FileID,fCode,FName,LName,FullName,FullName2,Mobile,A.MiladiDate,SendDateS,SendTime,
		ReferDate,ReferTime,DoctorName,DoctorName2,Status,TelegramStatus,SendType,SendStatus,
		TelegStatusTitle,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork,fCodeMonth,
		CASE WHEN Status =3 THEN Concat(CAST( CONVERT( Time, AnswerDate, 111) as nvarchar(5)),' - ', D.Shamsi) ELSE NULL END as AnswerDate
		, SentLabDate, IsActiveEmailLab
		
	FROM CTE A
	LEFT JOIN TblDate D ON CAST(A.AnswerDate as DATE) = D.MiladiDate
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, Status desc,
		ReferDate DESC , SendType, ReferTime
		
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Telegram_Ready]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Telegram_Ready] AS
BEGIN
	WITH CTE AS
	(
	SELECT 
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SendDate,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	WHERE 
		IsActiveTelegLab =1 and 
		TelegramLab is not NULL and
		fCode is not null and 
		status =3  and 
		ISNULL(TryCount,0) <10 and
		TelegramStatus in( 1,3,5) -- Queue or filenotfound or Faild 
	)
	SELECT TOP 1 
		FileID,fCode,FName,LName,Mobile,MiladiDate,ReferDate,DoctorName,Status,
		TelegramStatus,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork,TitleContent 
	FROM CTE A
	WHERE ISNULL( DATEDIFF(Minute, SendDate, Getdate()),999)>=5
	ORDER BY TryCount,SendDate,FileID 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Telegram_Ready_OLD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Telegram_Ready_OLD] AS
BEGIN
	WITH CTE AS
	(
	SELECT
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SendDate,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN FilesTable FT ON FT.FileID = TP.FileID
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor
	WHERE 
		IsActiveTelegLab =1 and 
		TelegramLab is not NULL and
		fCode is not null and 
		status =3  and 
		ISNULL(TryCount,0) <10 and
		TelegramStatus in( 1,3,5) -- Queue or filenotfound or Faild 
	UNION
	SELECT 
		TP.FileID, fCode, TP.FName, TP.LName, Mobile, MiladiDate, TP.ReferDate, TP.DoctorName,
		Status, TelegramStatus, TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,SendDate,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf'),
		TitleContent= 
				
				N' پزشک گرامي ' +CHAR(13)+CHAR(10)+
				N' دکتر ' +TP.DoctorName collate SQL_Latin1_General_CP1256_CI_AS +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				N' جواب آزمايش ' +Concat(TP.FName collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) +CHAR(13)+CHAR(10)+
				N' به تاريخ   '+ TP.ReferDate +	CHAR(13)+CHAR(10)+
				N' و تلفن   '+ TP.Mobile +CHAR(13)+CHAR(10)+
				CHAR(13)+CHAR(10)+
				--N' ارسال شد '+CHAR(13)+CHAR(10)+
				N' با احترام '+	CHAR(13)+CHAR(10)+
				N' آزمايشگاه پاتوبيولوژي پارس طب '			
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	WHERE 
		IsActiveTelegLab =1 and 
		TelegramLab is not NULL and
		fCode is not null and 
		status =3  and 
		ISNULL(TryCount,0) <10 and
		TelegramStatus in( 1,3,5) -- Queue or filenotfound or Faild 
	)
	SELECT TOP 1 
		FileID,fCode,FName,LName,Mobile,MiladiDate,ReferDate,DoctorName,Status,
		TelegramStatus,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork,TitleContent 
	FROM CTE A
	WHERE ISNULL( DATEDIFF(Minute, SendDate, Getdate()),999)>=5
	ORDER BY TryCount,SendDate,FileID 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Telegram_Teb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Telegram_Teb]( @Date nvarchar(10), @Done int) AS
BEGIN
	--DECLARE @Date nvarchar(10)= '1396/04/28', @Done int=0;
	DECLARE @FromDate nvarchar(10);
	
	SELECT @FromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 EMailDays from ConfigTable), MiladiDate) )
	FROM TblDate A 
	WHERE A.Shamsi = @Date
	;WITH CTE AS
	( 
	SELECT 
		siWait,siFiles,PatientName,DoctorName,FullName as RefPlace, AttachedCount,
		SG_Status,SendType,SendStatus,Subject,BranchName,
		WaitDate,WaitTime, 
		TelegramStatus,
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId,TryCount,
		SendDate, TD.Shamsi as SendDateS,
		ManualTelegStatus,
		'ManualTelegStatusTitle'=
		CASE ISNULL(ManualTelegStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		ManualTelegDateS, 
		Format(SendDate,'HH:MM') as SendDateTime,
		Format(ManualTelegDate,'HH:MM') as ManualTelegDateTime
		
	FROM VW_Select_WaitList_Doc_Hospital H
	LEFT JOIN dbo.TblDate TD ON TD.MiladiDate = H.SendDate
	WHERE 
		WaitDate BETWEEN @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2 ) and 
		(SentEMail = 3  OR ManualTelegDate IS NOT NULL) AND
		IsActiveTelegTeb = 1 and -- آيا تلگرام فعال است
		TelegramTeb IS NOT NULL  -- آيا شماره تلگرام دارد		
		 
	)

	SELECT 	
		siWait,siFiles,PatientName,DoctorName,RefPlace,AttachedCount,
		SG_Status,SendType,SendStatus,Subject,BranchName,
		WaitDate,WaitTime, 
		IIF( ISNULL( SendDateS,'1300/01/01')>= ISNULL( ManualTelegDateS,'1300/01/01'),TelegramStatus,ManualTelegStatus) as  TelegramStatus,  
		IIF( ISNULL( SendDateS,'1300/01/01')>= ISNULL( ManualTelegDateS,'1300/01/01'),TelegStatusTitle,ManualTelegStatusTitle) as  TelegStatusTitle,  
		IIF( ISNULL( SendDateS,'1300/01/01')>= ISNULL( ManualTelegDateS,'1300/01/01'),SendDateS,ManualTelegDateS) as  SendDateS,  
		IIF( ISNULL( SendDateS,'1300/01/01')>= ISNULL( ManualTelegDateS,'1300/01/01'),SendDateTime,ManualTelegDateTime) as  SendDateTime
	FROM CTE	
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, 
		WaitDate DESC , SendType, WaitTime
		
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_User_For_Manage]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE PROC [dbo].[USP_Select_User_For_Manage]( @siUser int) AS
SELECT     siUser, UserName, Password, IsAdmin
FROM  UserTable
WHERE siUser <> @siUser 
ORDER BY  UserName 








GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Editors]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Wait_Editors](@FromDate varchar(10),@ToDate varchar(10),@CheckEMail int, @Done int, @NonEditedCount Int OUT) AS              
BEGIN              
	--Declare @FromDate varchar(10)='1396/05/01',@ToDate varchar(10)='1396/05/05', @CheckEMail int=1, @Done int=0, @NonEditedCount int 
 
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 
DECLARE @Rec_Count int=0;
	
	SELECT  @Rec_Count= Count(*)
	FROM  VW_Select_WaitList_Doc_Hospital HPT 
	INNER JOIN AlbumTable ALT ON HPT.siFiles = ALT.siFiles
	WHERE ALT.SurgDate IS NULL and
		(@FromDate IS NULL OR WaitDate >= @FromDate) AND 
		(@ToDate IS NULL OR WaitDate <= @ToDate) AND 
		( Status = 16 ) AND
		(ISNULL(@CheckEMail,0)=0 OR ISNULL(HPT.IsActiveEMail,0) = 1 ) AND
		( ISNULL(Edited,0) =0 OR ISNULL(Printed,0)=0)
 
	SET @NonEditedCount =@Rec_Count;
 
SELECT
   siWait, Tbl.siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
   Tbl.Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
   FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
   siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
   IsActiveEMail, EMail1, EMail2, Description,Is3D,CASE Is3d When 0 then NULL else '3D' end Is3DTitle,IsFirstPrint
FROM(
		 SELECT               
		   siWait, HPT.siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		   Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName,siBranch,BranchName, 
		   'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), FullName, HPT.WaitCheck, HPT.MachineCheck,      
		   SendType,SendStatus,MachinePhoto,ISNULL(Edited,0) Edited,ISNULL(Printed,0) Printed,
		   'EditedTitle' =CASE ISNULL(Edited,0)  WHEN 0 THEN NULL ELSE  N'صادر شد' END ,-- برگه ويرايش
		   'PrintedTitle'=CASE ISNULL(Printed,0) WHEN 0 THEN NULL ELSE N'چاپ شد'   END , -- ليبل
		   'Finished'  	 =CASE WHEN ISNULL(Edited,0) = 1 AND ISNULL(Printed,0) = 1 THEN 1 ELSE 0  END ,-- آماده ايميل
		   HPT.SentEMail,HPT.EMailDate,HPT.EMailTime,HPT.AttachedCount,HPT.SentSMS,
		   Case ISNULL(SentEMail,0) 
						WHEN 0 THEN NULL
						WHEN 1 THEN N'صف'
						WHEN 2 THEN N'Failed'
						WHEN 3 THEN N'ارسال'
			END SentEMailTitle,-- ايميل
		   CASE ISNULL(SentSMS,0) WHEN 0 THEN NULL ELSE  N'ارسال' END SentSMSTitle,-- SMS
		   HPT.IsActiveEMail, HPT.EMail1, HPT.EMail2, Description, Is3D,IsFirstPrint
			
		 FROM  VW_Select_WaitList_Doc_Hospital HPT 
		 INNER JOIN AlbumTable ALT ON HPT.siFiles = ALT.siFiles
		 WHERE 
			  (@FromDate IS NULL OR WaitDate >= @FromDate) AND 
			  (@ToDate IS NULL OR WaitDate <= @ToDate) AND 
			  ( Status = 16 ) AND
			  (ISNULL(@CheckEMail,0)=0 OR ( ISNULL(HPT.IsActiveEMail,0) = 1  AND ISNULL(Printed,0)=1 AND ISNULL(Edited,0)=1 ) AND( @Done =1 OR ISNULL(SentEMail,0) <> 3 ) )
			  AND
			  ( ISNULL(@CheckEMail,0)=1 OR @Done = 1 OR ISNULL(Printed,0)=0 OR ISNULL(Edited,0)=0  )
	) Tbl
 
LEFT JOIN Wait3DTable W3d ON W3d.siFiles = Tbl.siFiles and Tbl.Is3D =1 and W3d.Status >= 20
WHERE   Is3D =0 OR (Is3D = 1 and siWait3D is not null)
 
ORDER BY 
	IIF(ISNULL(@CheckEMail,0)=1,
	CASE ISNULL(SentEMail,0) 
		WHEN 2 THEN NULL
		WHEN 0 THEN 1
		ELSE 2
	END,NULL), 
	CASE ISNULL(@CheckEMail,0)
		WHEN 0 THEN Finished
		WHEN 1 THEN ISNULL(SentEMail,0)
	END, 	
	WaitDate DESC,	
	SendType,		
	WaitTimeOut 
 
END               
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Editors_Total]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Wait_Editors_Total](@FromDate varchar(10),@ToDate varchar(10), @Done int) WITH RECOMPILE AS 
BEGIN              
	--DECLARE @FromDate varchar(10)='1396/05/01',@ToDate varchar(10)='1396/05/16', @CheckEMail int=1, @Done int=1 
 
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 
	DECLARE @Rec_Count int=0;
	DECLARE @TelegFromDate nvarchar(10);
 
	SELECT @TelegFromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 EMailDays from ConfigTable), MiladiDate) )
	FROM TblDate A  with(nolock)
	WHERE A.Shamsi = @ToDate
 
	;WITH CTE AS
	(
		 SELECT               
			siWait, HPT.siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
			Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName,siBranch,BranchName, 
			'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), 
			FullName, 
			HPT.WaitCheck, 
			HPT.MachineCheck,      
			SendType,
			SendStatus,MachinePhoto,ISNULL(Edited,0) Edited,ISNULL(Printed,0) Printed,
			'EditedTitle' =CASE ISNULL(Edited,0)  WHEN 0 THEN NULL ELSE  N'صادر شد' END ,-- برگه ويرايش
			'PrintedTitle'=CASE ISNULL(Printed,0) WHEN 0 THEN NULL ELSE N'چاپ شد'   END , -- ليبل
			'Finished'  	 =CASE WHEN ISNULL(Edited,0) = 1 AND ISNULL(Printed,0) = 1 THEN 1 ELSE 0  END ,-- آماده ايميل
			HPT.SentEMail,HPT.EMailDate,HPT.EMailTime,HPT.AttachedCount, HPT.SentSMS,
			Case ISNULL(SentEMail,0) 
						WHEN 0 THEN NULL
						WHEN 1 THEN N'صف'
						WHEN 2 THEN N'Failed'
						WHEN 3 THEN N'ارسال'
			END SentEMailTitle,-- ايميل
			CASE ISNULL(SentSMS,0) WHEN 0 THEN NULL ELSE  N'ارسال' END SentSMSTitle,
			ISNULL(HPT.IsActiveEMail,0) as IsActiveEMail, HPT.EMail1, HPT.EMail2,
			TelegramStatus,HPT.AttachedCountTeleg,
			'TelegStatusTitle'=
			CASE ISNULL(TelegramStatus,0)
						WHEN	0	THEN N''
						WHEN	1	THEN N'صف'
						WHEN	2	THEN N'ارسال'
						WHEN	3	THEN N'فايل يافت نشد'
						WHEN	4	THEN N''
						WHEN	5	THEN N'Failed'
			END,
			TelegMessageId,
			IsAuto,
			TryCount,
			SendDate, 
			TD.Shamsi as SendDateS,
			ManualTelegStatus,
			'ManualTelegStatusTitle'=
			CASE ISNULL(ManualTelegStatus,0)
						WHEN	0	THEN N''
						WHEN	1	THEN N'صف'
						WHEN	2	THEN N'ارسال'
						WHEN	3	THEN N'فايل يافت نشد'
						WHEN	4	THEN N''
						WHEN	5	THEN N'Failed'
			END,
			AutoOrManual,
			ManualTelegDateS, ManualTelegDate,
			Format(SendDate,'HH:mm') as SendDateTime,
			Format(ManualTelegDate,'HH:mm') as ManualTelegDateTime,
			HasTelegram=IIF(IsActiveTelegTeb = 1 AND TelegramTeb IS NOT NULL,1,0),
			ISNULL(HasFilterList ,0) as HasFilterList
			,Is3D
 
		 FROM  VW_Select_WaitList_Doc_Hospital HPT with(nolock)
		 INNER JOIN AlbumTable ALT  with(nolock) ON HPT.siFiles = ALT.siFiles
	 	 LEFT JOIN dbo.TblDate TD   with(nolock) ON TD.MiladiDate = CAST(HPT.SendDate as DATE)
		 WHERE 
			(		-- EMail Conditions 
			  (@FromDate IS NULL OR WaitDate >= @FromDate)	AND 
			  (@ToDate IS NULL OR WaitDate <= @ToDate)		AND 
			  ( Status = 16 ) AND
			  (( ISNULL(HPT.IsActiveEMail,0) = 1  AND ISNULL(Printed,0)=1 AND ISNULL(Edited,0)=1 ) AND( @Done =1 OR ISNULL(SentEMail,0) <> 3 ) )
			  
			)
			OR
			(		-- Telegram Conditions  
				WaitDate BETWEEN @TelegFromDate and  @ToDate	AND
				( @Done =1 OR 
					( AutoOrManual='A' AND ISNULL(TelegramStatus,0) <> 2) OR	
					( AutoOrManual='M' AND ISNULL(ManualTelegStatus,0) <> 2) 			
				)	AND 
				( ISNULL(Printed,0)=1 AND ISNULL(Edited,0)=1  ) AND
				IsActiveTelegTeb = 1 AND -- آيا تلگرام فعال است
				TelegramTeb IS NOT NULL  -- آيا شماره تلگرام دارد	
				AND ( ISNULL(HasFilterList ,0) = 0 OR AutoOrManual='M')  
			)
	),
	CTE1 AS
	(
	SELECT
		siWait, 
		siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
		FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
		siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
		IsActiveEMail, EMail1, EMail2,
		AttachedCountTeleg, IsAuto,
		HasTelegram, HasFilterList, Is3D,
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),TelegramStatus,ManualTelegStatus) as  TelegramStatus,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),TelegStatusTitle,ManualTelegStatusTitle) as  TelegStatusTitle,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),SendDateS,ManualTelegDateS) as  SendDateS,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),SendDateTime,ManualTelegDateTime) as  SendDateTime
	FROM CTE
	)
	,CTE2 AS
	(
	SELECT 
	siWait, HasFilterList,
		siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
		FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
		siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
		IsActiveEMail, EMail1, EMail2, AttachedCountTeleg, IsAuto,HasTelegram,
		EmailSeq= 
			Case 
				When IsActiveEMail=0		then 99
				When ISNULL(SentEMail,0)=2	then 1 -- Fail
				When ISNULL(SentEMail,0)=0	then 2 -- List
				When ISNULL(SentEMail,0)=1	then 3 -- Queue
				When ISNULL(SentEMail,0)=3	then 4 -- Sent
			end,
		TelegSeq= 
			Case 
				When HasTelegram=0							then 99 
				When ISNULL(TelegramStatus,0) in (3,4,5)	then 11 -- Fail
				When ISNULL(TelegramStatus,0)=0				then 12	-- List
				When ISNULL(TelegramStatus,0)=1				then 13	-- Queue
				When ISNULL(TelegramStatus,0)=2				then 14	-- Sent
			end,
		TelegramStatus,TelegStatusTitle,SendDateS,SendDateTime
		,Is3D
		
	FROM CTE1
	)
 
SELECT 
 
EMailTeleg = 
		CASE 
			WHEN IsActiveEMail=1 and HasTelegram=0  THEN 'E'
			WHEN IsActiveEMail=0 and HasTelegram=1  THEN 'T'
			WHEN IsActiveEMail=1 and HasTelegram=1  THEN 'ET'
		END,
SendQueue=
		CASE 
			WHEN EmailSeq = 1  OR TelegSeq =11  THEN 1
			WHEN EmailSeq = 3  OR TelegSeq =13  THEN 3
			WHEN EmailSeq = 2  OR (TelegSeq =12 and HasFilterList <>1)  THEN 2
			WHEN EmailSeq = 4  OR TelegSeq =14  THEN 4
		END,
		siWait, 
		siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
		FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
		siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
		IsActiveEMail, EMail1, EMail2,
		AttachedCountTeleg, IsAuto,HasTelegram,
		TelegramStatus,TelegStatusTitle,SendDateS,SendDateTime
		,Is3D
FROM CTE2
ORDER BY 
	SendQueue,
	WaitDate DESC,	
	SendType,		
	WaitTimeOut 
 
END               
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Editors_Total2]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Wait_Editors_Total2](@FromDate varchar(10),@ToDate varchar(10), @Done int) WITH RECOMPILE AS 
BEGIN              
	--DECLARE @FromDate varchar(10)='1396/05/01',@ToDate varchar(10)='1396/05/16', @CheckEMail int=1, @Done int=0 

     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           

	DECLARE @Rec_Count int=0;
	DECLARE @TelegFromDate nvarchar(10);

	SELECT @TelegFromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 EMailDays from ConfigTable), MiladiDate) )
	FROM TblDate A  with(nolock)
	WHERE A.Shamsi = @ToDate

	;WITH CTE AS
	(
		 SELECT               
			siWait, HPT.siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
			Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName,siBranch,BranchName, 
			'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), 
			FullName, 
			HPT.WaitCheck, 
			HPT.MachineCheck,      
			SendType,
			SendStatus,MachinePhoto,ISNULL(Edited,0) Edited,ISNULL(Printed,0) Printed,
			'EditedTitle' =CASE ISNULL(Edited,0)  WHEN 0 THEN NULL ELSE  N'صادر شد' END ,-- برگه ويرايش
			'PrintedTitle'=CASE ISNULL(Printed,0) WHEN 0 THEN NULL ELSE N'چاپ شد'   END , -- ليبل
			'Finished'  	 =CASE WHEN ISNULL(Edited,0) = 1 AND ISNULL(Printed,0) = 1 THEN 1 ELSE 0  END ,-- آماده ايميل
			HPT.SentEMail,HPT.EMailDate,HPT.EMailTime,HPT.AttachedCount, HPT.SentSMS,
			Case ISNULL(SentEMail,0) 
						WHEN 0 THEN NULL
						WHEN 1 THEN N'صف'
						WHEN 2 THEN N'Failed'
						WHEN 3 THEN N'ارسال'
			END SentEMailTitle,-- ايميل
			CASE ISNULL(SentSMS,0) WHEN 0 THEN NULL ELSE  N'ارسال' END SentSMSTitle,
			ISNULL(HPT.IsActiveEMail,0) as IsActiveEMail, HPT.EMail1, HPT.EMail2,
			TelegramStatus,HPT.AttachedCountTeleg,
			'TelegStatusTitle'=
			CASE ISNULL(TelegramStatus,0)
						WHEN	0	THEN N''
						WHEN	1	THEN N'صف'
						WHEN	2	THEN N'ارسال'
						WHEN	3	THEN N'فايل يافت نشد'
						WHEN	4	THEN N''
						WHEN	5	THEN N'Failed'
			END,
			TelegMessageId,
			IsAuto,
			TryCount,
			SendDate, 
			TD.Shamsi as SendDateS,
			ManualTelegStatus,
			'ManualTelegStatusTitle'=
			CASE ISNULL(ManualTelegStatus,0)
						WHEN	0	THEN N''
						WHEN	1	THEN N'صف'
						WHEN	2	THEN N'ارسال'
						WHEN	3	THEN N'فايل يافت نشد'
						WHEN	4	THEN N''
						WHEN	5	THEN N'Failed'
			END,
			AutoOrManual,
			ManualTelegDateS, ManualTelegDate,
			Format(SendDate,'HH:mm') as SendDateTime,
			Format(ManualTelegDate,'HH:mm') as ManualTelegDateTime,
			HasTelegram=IIF(IsActiveTelegTeb = 1 AND TelegramTeb IS NOT NULL,1,0)

		 FROM  VW_Select_WaitList_Doc_Hospital HPT with(nolock)
		 INNER JOIN AlbumTable ALT  with(nolock) ON HPT.siFiles = ALT.siFiles
	 	 LEFT JOIN dbo.TblDate TD   with(nolock) ON TD.MiladiDate = CAST(HPT.SendDate as DATE)

		 WHERE 
			(		-- EMail Conditions 
			  (@FromDate IS NULL OR WaitDate >= @FromDate)	AND 
			  (@ToDate IS NULL OR WaitDate <= @ToDate)		AND 
			  ( Status = 16 ) AND
			  (( ISNULL(HPT.IsActiveEMail,0) = 1  AND ISNULL(Printed,0)=1 AND ISNULL(Edited,0)=1 ) AND( @Done =1 OR ISNULL(SentEMail,0) <> 3 ) )
			  
			)
			OR
			(		-- Telegram Conditions  
				WaitDate BETWEEN @TelegFromDate and  @ToDate	AND
				( @Done =1 OR 
					(  AutoOrManual='A' AND ISNULL(TelegramStatus,0) <> 2) OR	
					(  AutoOrManual='M' AND ISNULL(ManualTelegStatus,0) <> 2) 			
				)	AND 
				( ISNULL(Printed,0)=1 AND ISNULL(Edited,0)=1  ) AND
				IsActiveTelegTeb = 1 AND -- آيا تلگرام فعال است
				TelegramTeb IS NOT NULL  -- آيا شماره تلگرام دارد		
			)
	),
	CTE2 AS
	(
	SELECT
		siWait, 
		siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
		FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
		siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
		IsActiveEMail, EMail1, EMail2,
		AttachedCountTeleg, IsAuto,
		HasTelegram, 
		EMailORDER = IIF(IsActiveEMail=1,ISNULL(SentEMail,0),99),
		--TelegORDER = IIF(HasTelegram=1,ISNULL(TelegramStatus,0),99),
		TelegORDER = IIF(HasTelegram=1,
					ISNULL(	
							IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),TelegramStatus,ManualTelegStatus) 
						,0)
						,99),  

		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),TelegramStatus,ManualTelegStatus) as  TelegramStatus,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),TelegStatusTitle,ManualTelegStatusTitle) as  TelegStatusTitle,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),SendDateS,ManualTelegDateS) as  SendDateS,  
		IIF( ISNULL( SendDate,'2000/01/01')>= ISNULL( ManualTelegDate,'2000/01/01'),SendDateTime,ManualTelegDateTime) as  SendDateTime
	FROM CTE
	)
SELECT 
EMailORDER,TelegORDER,
EMailTeleg = 
		CASE 
			WHEN IsActiveEMail=1 and HasTelegram=0  THEN 'E'
			WHEN IsActiveEMail=0 and HasTelegram=1  THEN 'T'
			WHEN IsActiveEMail=1 and HasTelegram=1  THEN 'ET'
		END,
SendQueue=
		CASE 
			WHEN EMailORDER = 2    OR (TelegORDER  >2 and TelegORDER  <99) THEN -5
			WHEN EMailORDER IN(3, 99)   AND (TelegORDER = 1 or TelegramStatus=1 ) THEN -3
			WHEN EMailORDER IN(3, 99)   AND (TelegORDER = 2 or TelegramStatus=2 ) THEN TelegORDER
			WHEN EMailORDER IN(3, 99)   AND TelegORDER  = 0  THEN -4
			WHEN EMailORDER IN(3, 99)   AND TelegORDER = 99  THEN 2
			WHEN EMailORDER IN(3, 99)   AND TelegORDER <> 0  THEN TelegORDER
			WHEN EMailORDER = 0   THEN -4
			WHEN EMailORDER <> 99   THEN EMailORDER
			WHEN EMailORDER<TelegORDER THEN EMailORDER
			WHEN EMailORDER>=TelegORDER THEN TelegORDER
		END,
		siWait, 
		siFiles, WaitDate, WaitTime, WaitCall, WaitPhoto, WaitService, WaitTimeOut, SurgStatus, 
		Status, SG_Status, WaitStatus, PatientName, Subject, siDoctors, FileID, DoctorName, FullDoctorName, 
		FullName, SendType, SendStatus, MachinePhoto, Edited, Printed, EditedTitle, PrintedTitle, Finished,
		siBranch, BranchName, SentEMail, SentEMailTitle, EMailDate, EMailTime, AttachedCount, SentSMS, SentSMSTitle,
		IsActiveEMail, EMail1, EMail2,
		AttachedCountTeleg, IsAuto,HasTelegram,
		TelegramStatus,TelegStatusTitle,SendDateS,SendDateTime
		
FROM CTE2
ORDER BY 
	SendQueue,
	WaitDate DESC,	
	SendType,		
	WaitTimeOut 

END               
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Patients]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Wait_Patients](@StatusMode tinyint,@Date varchar(10), @siBranch int , @Caller int , @RecordCount Int OUT ) AS              
BEGIN              
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
	 ---------------------------
	 -- @Caller =1 -> منشي    @Caller =2 -> چکر   @Caller =3 -> فتوگرافر
	 ---------------------------
DECLARE @Rec_Count int=0;
	SELECT @Rec_Count= Count(*) FROM VW_Select_WaitList_Doc_Hospital
	WHERE               
	  (@siBranch =0 or  siBranch = @siBranch) AND 
	  (@Date IS NULL OR WaitDate = @Date) ;          
 
	SET @RecordCount =@Rec_Count;
	;WITH CTE AS
	(
		Select siWait, ISNULL(T71,0) BEF, ISNULL(T72,0) A4 , ISNULL(T73,0) OC, ISNULL(T76,0) AFT , ISNULL(T77,0) NOP , ISNULL(T84,0) EXT   
		from 
		(
			Select siWait,Concat('T',siCommonTariff) CommonTariff, Number 
			from ServiceTable S 
		) SRC
		PIVOT 
		(
			MIN(Number) FOR CommonTariff IN ([T71],[T72],[T73],[T76],[T77],[T84]) 
		)pvt
	)
	SELECT            
	   DH.siWait, DH.siFiles, WaitDate, WaitTime,WaitCall,WaitPhoto,WaitService, WaitTimeOut, SurgStatus, 
	   DH.Status, SG_Status, WaitStatus, PatientName,               
	   Subject, siDoctors, DH.FileID, DH.DoctorName, 'FullDoctorName' =DH.DoctorName + ' '+ Cast(DH.FileID AS varchar(5)), 
	   FullName, FactorStatus, 
	   DH.SendType,DH.SendStatus,MachinePhoto ,siBranch,BranchName , WaitCheck, MachineCheck, IsScanned,
	   '' as  LabStatus,
	   CAST(NULL as Datetime)  as RegisterDate, 
	   BEF,A4,OC,AFT,NOP,EXT,
	   ''  as RegisterDateS,
	   '' as RegisterTime,
 
	   'ScannedStatus' = 
						CASE IsScanned
							WHEN 0 THEN 'Faild' 
							WHEN -1 THEN 'NO' 
							ELSE NULL -- OK 
						END
		,Is3D
		,cast(convert(Time,TakePhoto) as varchar(5) ) as TakePhoto
		,CASE Is3d When 0 then NULL else '3D' end Is3DTitle
	FROM  VW_Select_WaitList_Doc_Hospital DH 
	LEFT JOIN CTE C ON C.siWait = DH.siWait
	LEFT JOIN Wait3DTable W3 ON W3.siFiles = DH.siFiles --and W3.Status >=5
	WHERE               
	  (@siBranch =0 or  siBranch = @siBranch) AND 
	  (@Caller =1 OR IsScanned <> -1 ) AND
	  (@Date IS NULL OR WaitDate = @Date) AND              
	  (( DH.Status = 1  AND @StatusMode IN( 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31)   )OR              
	   ( DH.Status = 2  AND @StatusMode IN( 2,3,6,7,10,11,14,15,18,19,22,23,26,27,30,31)  )OR              
	   ( DH.Status = 4  AND @StatusMode IN( 4,5,6,7,12,13,14,15,20,21,22,23,28,29,30,31)  )OR              
	   ( DH.Status = 8  AND @StatusMode IN( 8,9,10,11,12,13,14,15,24,25,26,27,28,29,30,31) )OR
	   ( DH.Status =16  AND @StatusMode IN( 16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 ) ))
	ORDER BY   
		  Status,WaitDate , WaitTimeOut DESC,WaitTime  
	             
END         
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Patients_BysiFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_Select_Wait_Patients_BysiFile]( @siFiles int ) AS          
BEGIN          
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 SELECT           
   siWait, siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, Status, SG_Status, WaitStatus, PatientName,siBranch,BranchName,           
   Subject, siDoctors, FileID, DoctorName, 'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), FullName, FactorStatus          
 FROM  VW_Select_WaitList_Doc_Hospital          
 WHERE siFiles = @siFiles          
END           
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Patients_ByWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_Select_Wait_Patients_ByWait]( @siWait int ) AS        
BEGIN        
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 SELECT         
   siWait, siFiles, WaitDate, WaitTime, WaitTimeOut, SurgStatus, Status, SG_Status, WaitStatus, PatientName,siBranch,BranchName,         
   Subject, siDoctors, FileID, DoctorName, 'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), FullName , FactorStatus        
 FROM  VW_Select_WaitList_Doc_Hospital        
 WHERE siWait = @siWait        
END         


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Patients2]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Select_Wait_Patients2](@StatusMode tinyint,@Date varchar(10), @siBranch int, @RecCount Int OUT) AS              
BEGIN              
     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
DECLARE @RecordCount int=0;
	SELECT @RecordCount= Count(*) FROM VW_Select_WaitList_Doc_Hospital
	WHERE               
	  (@siBranch =0 or  siBranch = @siBranch) AND 
	  (@Date IS NULL OR WaitDate = @Date)           
	SET @RecCount =@RecordCount;
	SELECT               
	   siWait, siFiles, WaitDate, WaitTime,WaitCall,WaitPhoto,WaitService, WaitTimeOut, SurgStatus, Status, SG_Status, WaitStatus, PatientName,               
	   Subject, siDoctors, FileID, DoctorName, 'FullDoctorName' =DoctorName + ' '+ Cast(FileID AS varchar(5)), FullName,      
	   SendType,SendStatus,MachinePhoto ,siBranch,BranchName , WaitCheck, MachineCheck, @RecordCount as RecCount           
	FROM  VW_Select_WaitList_Doc_Hospital              
	WHERE               
	  (@siBranch =0 or  siBranch = @siBranch) AND 
	  (@Date IS NULL OR WaitDate = @Date) AND              
	  (( Status = 1  AND @StatusMode IN( 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31)   )OR              
	   ( Status = 2  AND @StatusMode IN( 2,3,6,7,10,11,14,15,18,19,22,23,26,27,30,31)  )OR              
	   ( Status = 4  AND @StatusMode IN( 4,5,6,7,12,13,14,15,20,21,22,23,28,29,30,31)  )OR              
	   ( Status = 8  AND @StatusMode IN( 8,9,10,11,12,13,14,15,24,25,26,27,28,29,30,31) )OR
	   ( Status =16  AND @StatusMode IN( 16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 ) ))
	ORDER BY   
		  Status,WaitDate , WaitTimeOut DESC,WaitTime  
	             
END               


GO

/****** Object:  StoredProcedure [dbo].[USP_Select_Wait_Telegram_Ready]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE  [dbo].[USP_Select_Wait_Telegram_Ready]  AS
BEGIN
	DECLARE @EMailDays Int,@TebDelayTelegram int
 
	Select Top 1 @TebDelayTelegram=TebDelayTelegram FROM ConfigTable; 
	Select Top 1 @EMailDays =EMailDays  From ConfigTable;
 
	;WITH CTE AS
	(
		SELECT -- AUTOMATIC
			siWait,
			HPT.siFiles,
			HPT.siDoctors,
			HPT.FileID,
			PFName as FName,
			PLName as LName,
			Subject,
			WaitDate,
			WaitTimeOut,
			Phone1 as Mobile,
			Phone2, 
			NULL as MiladiDate, 
			BEF_AFT,
			ReferDate, 
			DoctorName2 as DoctorName,Status,
			TelegramTeb,
			TelegramStatus,
			TelegMessageId,
			TryCount,
			SendDate,
			PathEMail as ImagePath,
			PathEMail as ImageNetwork,
			Is3D
		FROM VW_Select_WaitList_Doc_Hospital HPT  
		LEFT JOIN VW_Select_ListOfFilesWithForbidenSurgery FR ON FR.siFiles = HPT.siFiles
		CROSS APPLY dbo.FN_GetFolderPathForPatient( HPT.siFiles ) PTH
		WHERE 
		    --HPT.siFiles NOT IN ( SELECT siFiles From VW_Select_ListOfFilesWithForbidenSurgery ) AND
			( Status =16 ) AND 
			ISNULL( Printed,0 ) =1 AND
			ISNULL( Edited,0 ) =1 AND 
			ManualTelegDate IS NULL AND 
			SentEMail = 3 AND 
			ISNULL( TelegramStatus,0 ) <> 2 AND
			ISNULL( HPT.IsActiveTelegTeb,0 )=1 AND
			TelegramTeb IS NOT NULL AND 
			HPT.IsAuto = 1 and 
			DATEDIFF(day, SentEMailTime, GetDate() )<= @EMailDays AND
			ISNULL( DATEDIFF(Minute, SendDate, Getdate()),999)>=@TebDelayTelegram AND
			FR.siFiles IS NULL 
		UNION
		SELECT --MANUAL
			siWait,
			HPT.siFiles,
			HPT.siDoctors,
			HPT.FileID,
			PFName as FName,
			PLName as LName,
			Subject,
			WaitDate,
			WaitTimeOut,
			Phone1 as Mobile,
			Phone2, 
			NULL as MiladiDate, 
			BEF_AFT,
			ReferDate, 
			DoctorName2 as DoctorName,Status,
			TelegramTeb,
			TelegramStatus,
			TelegMessageId,
			TryCount,
			SendDate,
			PathEMail as ImagePath,
			PathEMail as ImageNetwork,
			Is3D
		FROM VW_Select_WaitList_Doc_Hospital HPT  
		CROSS APPLY dbo.FN_GetFolderPathForPatient( HPT.siFiles ) PTH 
		WHERE 
			(Status =16 ) AND 
			ISNULL( Printed,0) =1 AND
			ISNULL(Edited,0) =1 AND 
			ManualTelegDate IS NOT NULL AND 
			ISNULL( HPT.IsActiveTelegTeb,0)=1 and
			TelegramTeb IS NOT NULL AND
			ISNULL(ManualTelegStatus,0) <>2 AND
			ISNULL( DATEDIFF(Minute, ManualTelegDate, Getdate()),999)>=@TebDelayTelegram 
	),
	CTE_Result AS
	(
	SELECT 
			siWait,
			siFiles,
			siDoctors,
			FileID,
			FName,
			LName,
			Mobile, 
			MiladiDate, 
			ReferDate,
			WaitTimeOut,
			DoctorName,
			Status,
			TelegramTeb,
			TelegramStatus,
			TelegMessageId,
			TryCount,
			ImagePath,
			ImageNetwork,
			Is3D,
			TitleContent= 		
				N'پزشک گرامي'  +CHAR(13)+CHAR(10)+N'دکتر '+DoctorName +CHAR(13)+CHAR(10)+
				N'مراجعه کننده ' +Concat(FName ,' ',LName) +CHAR(13)+CHAR(10)+
				N'به همراه:  '+ Mobile+ CHAR(13)+CHAR(10)+
   			    CASE WHEN ISNULL(Phone2,N'') <>N'' THEN N'به تلفن:  '+ Phone2+ CHAR(13)+CHAR(10) ELSE N'' END +
				N'در تاريخ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+CHAR(10)+
				N'موضوع: '+ Subject+' '+CHAR(13)+CHAR(10)+
				CASE BEF_AFT WHEN 1 THEN N'بعد از درمان' ELSE N'قبل از درمان' END +CHAR(13)+CHAR(10)+
				N'با تشکر طب نگار'
	FROM CTE 
	)
 
	SELECT	TOP 1
			siWait,
			A.FileID,
			A.FName,
			A.LName,
			Mobile, 
			MiladiDate, 
			A.ReferDate, 
			A.DoctorName,
			Status,
			TelegramTeb,
			TelegramStatus,
			TelegMessageId,
			TryCount,
			ImagePath,
			ImageNetwork,
			Is3D,
			TitleContent
				
	FROM CTE_Result A				
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, 
		ReferDate , WaitTimeOut 
 
END
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_WaitTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

CREATE Proc [dbo].[USP_Select_WaitTable] AS 
Begin
 Select  
	siWait,siFiles,WaitDate,WaitTime,WaitTimeOut,SurgStatus,Status,Comment
 From WaitTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Select_WaitTable_BySerial]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Select_WaitTable_BySerial](@siWait  int) AS 
Begin 
 Select  
	siWait,siFiles,WaitDate,WaitTime,WaitTimeOut,SurgStatus,Status,Comment,MachinePhoto
 From WaitTable
 Where siWait= @siWait
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_SeperateAddress]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_SeperateAddress]( @FileID int )  AS    
Begin    
 --Declare @FileID int  SET @FileID = 15    
 SET NOCOUNT ON    
 declare @I int, @Lines int ,@K int, @AD varchar(1000), @S varchar(1000)    
 SET @AD = NULL Set @I = 1  Set @K = 0     
    
 Select @S= LTRIM(RTRIM(Comment)) From CosmoPatient..DoctorsTable  Where FileID = @FileID    
    
 Update CosmoPatient..DoctorsTable    
   SET     
  Address1 = NULL, Address2 = NULL, Address3 = NULL, Address4 = NULL    
 Where FileID = @FileID    
    
 If @S = '' or @S IS NULL SET @I = 500    
 Set @Lines = dbo.CountOfLines(@S)+1    
 --SET @I = 500    
 While @I <= @Lines    
 begin     
  SET @K = CharIndex(Char(10),@S)     
  SET @AD = NULL     
  If @K > 0    
   SET @AD = LTRIM(RTRIM( Left(@S,@K-1) ))    
  else    
   SET @AD = LTRIM(RTRIM(@S))    
        
  If @I = 1 Update CosmoPatient..DoctorsTable  SET Address1 = @AD  Where FileID = @FileID    
  If @I = 2 Update CosmoPatient..DoctorsTable  SET Address2 = @AD  Where FileID = @FileID    
  If @I = 3 Update CosmoPatient..DoctorsTable  SET Address3 = @AD  Where FileID = @FileID    
  If @I = 4 Update CosmoPatient..DoctorsTable  SET Address4 = @AD  Where FileID = @FileID    
    
  IF @K = 0 Break    
  SET @S = STUFF(@S,1,@K,'')    
    
  SET @S = LTRIM(RTRIM(@S))     
  SET @I = @I +1    
 end       
end    
    

GO

/****** Object:  StoredProcedure [dbo].[USP_Set_FactorStatus]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Set_FactorStatus]( @siFiles int , @FactorStatus tinyint) AS
BEGIN
	UPDATE WaitTable 
		SET	FactorStatus= @FactorStatus
	WHERE siFiles= @siFiles
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Set_Permission]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE	PROCEDURE [dbo].[USP_Set_Permission] ( @siFiles int, @LoginName varchar(20) ) AS
BEGIN
	
	IF @LoginName in('quality','tebnegar') RETURN 0
	
	--IF EXISTS( Select * from PermissionTable Where siFile = @siFiles and LoginName  in (Select LoginName From  LoginGroup where IsGroup =1 ) )
	IF EXISTS( Select * from PermissionTable Where siFile = @siFiles  )
		RETURN 0
 
	DECLARE @Path nvarchar(1000)=''
	SELECT		
		@Path=F.PathFolder +'\'+T.FolderName+'\'+LTrim(RTrim(F.LName))+' '+LTrim(RTrim( F.FName ))+' '+LTrim(RTrim( F.FileID ) ) 
	FROM FilesTable F 
	INNER JOIN  DoctorsTable T ON F.siDoctor = T.siDoctors 
	WHERE F.siFiles = @siFiles
	
	IF @Path ='' RETURN
 
	DECLARE @Ret int,@TraceID INT , @Now Datetime = GETDATE(), @ProcName nvarchar(50)=OBJECT_NAME(@@PROCID); 
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC @TraceID = tools.RecordIt NULL ,  @ProcName, @Now, 'I', NULL,@siFiles
 
	DECLARE @ScriptGrant nvarchar(1000)='', @ScriptDeny nvarchar(1000)='',@Grants nvarchar(4000);
 
	SELECT @LoginName = LoginName FROM LoginGroup	WHERE IsGroup = 1
	SET @Grants  = N'xp_cmdshell N''C:\"Tebnegar Network Opened Files Service"\NOFC.bat /grant "'+@Path+ '" '+@LoginName+'''' 
 
FileExist:
	EXEC Master.dbo.xp_fileExist 'C:\Tebnegar Network Opened Files Service\req_cmd.inf' , @Ret output 
	IF @RET =1 
	BEGIN
		WAITFOR DELAY '00:00:00.100'
		GOTO FileExist
	END
 
	EXEC(@Grants)
 
	SET @Now = GETDATE()
	IF EXISTS (Select * from ConfigTable Where TraceEnables =1)  EXEC tools.RecordIt @TraceID ,  '', @Now, 'U', @Grants
 
	INSERT INTO PermissionTable(LoginName,Status,siFile,ScriptGrant,ScriptDeny,ActionTime)
	SELECT 
		LoginName,
		'G' Status, 
		@siFiles as siFile,
		N'xp_cmdshell N''ICACLS "'+@Path+'" /grant '+LoginName+':(OI)(CI)F /T '''  as ScriptGrant,
		N'xp_cmdshell N''ICACLS "'+@Path+'" /remove '+LoginName+' /T ''' as ScriptDeny
		, GetDate() as ActionTime
	FROM LoginGroup
	WHERE IsGroup =1
 
	RETURN 0
 
END
 

GO

/****** Object:  StoredProcedure [dbo].[USP_Set_Telegram]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Set_Telegram]( @FileID int, @Mode int ) AS
BEGIN
	UPDATE NovinTebnegarPatients
	SET 
		TelegramStatus= Case @Mode when 0 then  1 when 1 then NULL end, 
		TryCount= 0,
		TelegMessageId = NULL,
		SendDate= NULL
	WHERE FileID = @FileID  
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Set3DWait_Status]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_Set3DWait_Status](@siFiles int, @Status tinyint,@SetNULL tinyint=0 ) AS 
BEGIN
	
	DECLARE @ActionTime Datetime = GETDATE(), @OldStatus tinyint, @LastStatus tinyint;
	DECLARE @siWait int;
	SELECT @siWait= siWait From WaitTable Where siFiles = @siFiles;
	SELECT @OldStatus= Status From Wait3DTable Where siFiles = @siFiles
	IF @SetNULL =1
	BEGIN
		SET @ActionTime = NULL
		SELECT @LastStatus= LastStatus From Wait3DTable Where siFiles = @siFiles 
 
					--	CASE @Status
					--		WHEN 5  THEN 1
					--		WHEN 10 THEN 5
					--		WHEN 16 THEN 10
					--		WHEN 20 THEN 16
					--	END
	END
	
	IF @Status =1 AND NOT EXISTS( SELECT * FROM Wait3DTable WHERE siFiles = @siFiles)
	BEGIN
		INSERT INTO Wait3DTable(siFiles,Status,DeliveryTime) VALUES(@siFiles,@Status, GETDATE())
		RETURN SCOPE_IDENTITY()
	END
	
	IF NOT EXISTS( SELECT * FROM Wait3DTable WHERE siFiles = @siFiles)
		RETURN -1
	
	IF @SetNULL =1 and @Status = 1 and EXISTS(SELECT * FROM Wait3DTable WHERE siFiles = @siFiles and @LastStatus is null)
	BEGIN
		DELETE Wait3DTable WHERE siFiles = @siFiles
		UPDATE WaitTable SET Status = 2 ,WaitCall= NULL, MachinePhoto =NULL WHERE siFiles = @siFiles
	END
	ELSE
	BEGIN
 
		UPDATE Wait3DTable SET
			Status         = IIF(@SetNULL =0, @Status, @LastStatus),
			LastStatus     = @OldStatus,
			DeliveryTime   = @ActionTime,	--status =1
			TakePhoto      = NULL,			--status =5
			DenseCloudTime = NULL,			--status =10
			TebPaidTime    = NULL,			--status =16
			Object3DTime   = NULL			--status =20
		WHERE siFiles = @siFiles  and @Status = 1
		-- For 10
		IF @Status = 10
		BEGIN
			UPDATE Wait3DTable SET
				Status         = IIF(@SetNULL =0, 10, 5),
				LastStatus     = @OldStatus,
				DenseCloudTime = IIF(@SetNULL =0,@ActionTime,NULL), --status =10
				TebPaidTime    = NULL, --status =16
				Object3DTime   = NULL  --status =20
			WHERE siFiles = @siFiles  
		END
 
		UPDATE Wait3DTable SET
			Status		   = IIF(@SetNULL =0, @Status, @LastStatus),
			LastStatus     = @OldStatus,
			TakePhoto      = IIF(@Status = 5,@ActionTime,TakePhoto ),      --status =5
			DenseCloudTime = IIF(@Status =10,@ActionTime,DenseCloudTime ), --status =10
			TebPaidTime    = IIF(@Status =16,@ActionTime,TebPaidTime ),    --status =16
			Object3DTime   = IIF(@Status =20,@ActionTime,Object3DTime )    --status =20
		WHERE siFiles = @siFiles and @Status not in(1,10)
 
		Declare @WaitPhoto varchar(5) = LEFT(Cast( @ActionTime as Time ),5 );
		IF @Status =10 and @SetNULL = 0
		BEGIN
			EXEC USP_Update_WaitTable_Status @siWait, 4
			EXEC USP_Update_WaitTable_Photo @siWait, @WaitPhoto
		END
 
	END
END;
 
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_CheckForDeleteFiles]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_CheckForDeleteFiles] AS
BEGIN

	SELECT 
		DISTINCT
		FT.siFiles, FT.FileID, FT.FName, FT.LName, FT.ReferDate, 
		FT.DoctorName,FT.PathFolder,PT.LocalPath,
		DF.Status,

			'NetPath'= FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'NetPathFinal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'NetPathEMail'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'NetPathOriginal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'NetPathOther'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others',

			'WinPath'= PT.LocalPath+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'WinPathFinal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'WinPathEMail'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'WinPathOriginal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'WinPathOther'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others'


	FROM FilesTable FT
	INNER JOIN TblDate DT			ON DT.Shamsi	= FT.ReferDate
	INNER JOIN AlbumTable ALT		ON ALT.siFiles	= FT.siFiles
	INNER JOIN PathTable PT			ON PT.NetworkPath = PathFolder
	INNER JOIN AlbumSurgTable AST	ON AST.siAlbum = ALT.siAlbum
	INNER JOIN DoctorsTable DC		ON FT.siDoctor = DC.siDoctors
	LEFT  JOIN DeletedFilesTable DF	ON DF.FileID = FT.FileID 
	WHERE 
		AST.siSurgery in (31,32,33,34,35,42) AND 
		
		ISNULL(DF.Status,0) not in( 3 , 10 )AND 

		MiladiDate < DATEADD( Day, (Select Top 1 -DeleteDays from ConfigTable) , GetDate() )  

	ORDER BY FT.sifiles DESC 
 /*
  0- Queue;
  1- Copied;
  2- Deleted; reserved
  3- Final Path not Exists;
  4- Original Path not Exists;
  5- Other Path not Exists;
 10- Complited;
 */
END

GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_CheckForDeleteFilesParams]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_CheckForDeleteFilesParams]( @ParamList as varchar(100)) AS
BEGIN
	
	SELECT 
		DISTINCT
		FT.siFiles, FT.FileID, FT.FName, FT.LName, FT.ReferDate, 
		FT.DoctorName,FT.PathFolder,PT.LocalPath,
		DF.Status,

			'NetPath'= FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'NetPathFinal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'NetPathEMail'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'NetPathOriginal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'NetPathOther'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others',

			'WinPath'= PT.LocalPath+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'WinPathFinal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'WinPathEMail'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'WinPathOriginal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'WinPathOther'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others'


	FROM FilesTable FT
	INNER JOIN TblDate DT			ON DT.Shamsi	= FT.ReferDate
	INNER JOIN AlbumTable ALT		ON ALT.siFiles	= FT.siFiles
	INNER JOIN PathTable PT			ON PT.NetworkPath = PathFolder
	INNER JOIN AlbumSurgTable AST	ON AST.siAlbum = ALT.siAlbum
	INNER JOIN DoctorsTable DC		ON FT.siDoctor = DC.siDoctors
	LEFT  JOIN DeletedFilesTable DF	ON DF.FileID = FT.FileID 
	WHERE 
		AST.siSurgery in (31,32,33,34,35,42) AND 
		--ISNULL(DF.Status,0) not in( 3 , 10 )AND 
		ISNULL(DF.Status,0) in ( SELECT Item FROM dbo.FN_StringToTable_Not_NULL(@ParamList+',8',',') ) AND
		MiladiDate < DATEADD( Day, (Select Top 1 -DeleteDays from ConfigTable) , GetDate() )  

	ORDER BY FT.sifiles  
 /*
  0- Queue;
  1- Copied;
  2- Deleted; reserved
  3- Final Path not Exists;
  4- Original Path not Exists;
  5- Other Path not Exists;
 10- Complited;
 */
END
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_CheckForDeleteOthers]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_CheckForDeleteOthers]( @DateBefore as varchar(10)) AS
BEGIN
	
	SELECT 
		DISTINCT 
		FT.siFiles, FT.FileID, FT.FName, FT.LName, FT.ReferDate, 
		FT.DoctorName,FT.PathFolder,PT.LocalPath,

			'NetPath'= FT.PathFolder+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'NetPathFinal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'NetPathEMail'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'NetPathOriginal'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'NetPathOther'=FT.PathFolder+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others',

			'WinPath'= PT.LocalPath+'\'+
					Dc.FolderName+'\'+
					FT.LName+' '+
					FT.FName+' '+ 
					CAST(FT.FileId AS NVARCHAR(200)),
			'WinPathFinal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Final',
			'WinPathEMail'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-EMail',
			'WinPathOriginal'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Original',
			'WinPathOther'=PT.LocalPath+'\'+
						Dc.FolderName+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+'\'+
						FT.LName+' '+
						FT.FName+' '+ 
						CAST(FT.FileId AS NVARCHAR(200))+
						'-Others'


	FROM FilesTable FT
	INNER JOIN PathTable PT			ON PT.NetworkPath = PathFolder
	INNER JOIN DoctorsTable DC		ON FT.siDoctor = DC.siDoctors
	LEFT  JOIN DeletedOthersTable O ON O.FileID = FT.FileID and Status =10
	WHERE ReferDate < @DateBefore and O.siDeletedOthers IS NULL 
	ORDER BY FT.sifiles  
 /*
  0- Queue;
  1- Copied;
  2- Deleted; reserved
  3- Final Path not Exists;
  4- Original Path not Exists;
  5- Other Path not Exists;
  9- Error occured
 10- Complited;
 */
END
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_CopyNewPatientIntoNovin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_CopyNewPatientIntoNovin] AS
BEGIN
	INSERT INTO  NovinTebnegarPatients
		(FileID, FName, LName, Phone1,Mobile, SendType, SendStatus, BirthYear, 
		 MiladiDate, ReferDate, DoctorName, MedicalID, Sex, SexTitle, Status, TelegramStatus)
	SELECT 
		FT.FileID, 
		FT.FName,  
		FT.LName, 
		Phone1 = IIF( LEFT(Replace(Replace(';'+Phone1,';0',''),';',''),1)='9',NULL,Phone1),	
		Mobile = IIF( LEFT(Replace(Replace(';'+Phone1,';0',''),';',''),1)='9',Phone1,NULL),			 
		SendType,
		'SendStatus' = CASE SendType           
			WHEN 0 THEN 'اورژانس'           
			WHEN 1 THEN 'عادي'           
		END ,  
		BirthYear, 
		MiladiDate,  
		ReferDate, 
		ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'')  DoctorName, 
		DT.MedicalID ,
		Sex,
		'SexTitle' = CASE Sex           
			 WHEN 0 THEN 'زن'
			 WHEN 1 THEN 'مرد'           
		END,
		0 Status,
		0 TelegramStatus
 
	FROM FilesTable FT (nolock)
	INNER JOIN DoctorsTable DT (nolock) ON DT.siDoctors = FT.siDoctor
	LEFT JOIN TblDate TD (nolock) ON FT.ReferDate = TD.Shamsi
	WHERE 
		(CAST(DATEADD(DAY,(SELECT -NovinDelayDay FROM ConfigTable),GETDATE()) as DATE) <= TD.MiladiDate ) 
		
	DELETE FROM NovinTebnegarPatients
	WHERE (RegisterDate IS NULL) AND  DATEDIFF(Day,Miladidate, Getdate()) >= (SELECT TOP 1 NovinDelayDay FROM ConfigTable )
 
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_CreateForbidenWords]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_SYS_CreateForbidenWords]( @siList varchar(1000) ) AS
Begin
	Declare @Words varchar(500) = ';'
	Set @siList = ','+@siList+',';

	Select @Words = @Words+ ','+ Cast(SurgeryName  as varchar(5) )
	From SurgeryTable A
	Where CHARINDEX(','+CAST(siSurgery as varchar(2))+',',@siList)>0 

	Select Replace( @Words,';,','' ) as ForbidenList
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_Get_Time_Date]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_SYS_Get_Time_Date] AS  
 SELECT dbo.FN_DateToShamsi( GetDate() ) AS ServerDate, CONVERT(VARCHAR(5),GETDATE(),108) AS ServerTime  

GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_GetProcInfo]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









CREATE PROCEDURE [dbo].[USP_SYS_GetProcInfo]( @ProcName varchar(4000) ) AS
BEGIN
	CREATE TABLE #TEMP
	(
	PROCEDURE_QUALIFIER nvarchar(4000),
	PROCEDURE_OWNER nvarchar(4000),
	PROCEDURE_NAME nvarchar(4000),
	COLUMN_NAME nvarchar(4000),
	COLUMN_TYPE smallint,
	DATA_TYPE smallint,
	[TYPE_NAME] nvarchar(4000),
	[PRECISION] int,
	LENGTH int,
	SCALE smallint,
	RADIX smallint,
	NULLABLE smallint,
	REMARKS nvarchar(4000),
	COLUMN_DEF nvarchar(4000),
	SQL_DATA_TYPE smallint,
	SQL_DATETIME_SUB smallint,
	CHAR_OCTET_LENGTH int,
	ORDINAL_POSITION int,
	IS_NULLABLE nvarchar(254),
	SS_DATA_TYPE tinyint
	)

	INSERT INTO #TEMP EXEC sp_sproc_columns @procedure_name = @procname
	SELECT
	'ParamName' = COLUMN_NAME ,
	'ParamType' = COLUMN_TYPE ,
	[Type_name] ,
	[Precision] ,
	Length ,
	Scale
	FROM #TEMP

	DROP TABLE #TEMP
END








GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_GetProcInfo_NO_AT]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









--EXEC  USP_SYS_GetProcInfo_NO_AT USP_Insert_FilesTable

CREATE PROCEDURE [dbo].[USP_SYS_GetProcInfo_NO_AT]( @ProcName varchar(4000) ) AS  
BEGIN  
 CREATE TABLE #TEMP  
 (  
 PROCEDURE_QUALIFIER nvarchar(4000),  
 PROCEDURE_OWNER nvarchar(4000),  
 PROCEDURE_NAME nvarchar(4000),  
 COLUMN_NAME nvarchar(4000),  
 COLUMN_TYPE smallint,  
 DATA_TYPE smallint,  
 [TYPE_NAME] nvarchar(4000),  
 [PRECISION] int,  
 LENGTH int,  
 SCALE smallint,  
 RADIX smallint,  
 NULLABLE smallint,  
 REMARKS nvarchar(4000),  
 COLUMN_DEF nvarchar(4000),  
 SQL_DATA_TYPE smallint,  
 SQL_DATETIME_SUB smallint,  
 CHAR_OCTET_LENGTH int,  
 ORDINAL_POSITION int,  
 IS_NULLABLE nvarchar(254),  
 SS_DATA_TYPE tinyint  
 )  
  
 INSERT INTO #TEMP EXEC sp_sproc_columns @procedure_name = @procname  
 SELECT  
 'ParamName' = Right(COLUMN_NAME,Len(COLUMN_NAME)-1) ,  
 'ParamType' = COLUMN_TYPE ,  
 [Type_name] ,  
 [Precision] ,  
 Length ,  
 Scale  
 FROM #TEMP  
  
 DROP TABLE #TEMP  
END  









GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_LinkDoctorToNovin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC	[dbo].[USP_SYS_LinkDoctorToNovin]( @FileId varchar(15), @siDoctor Int ) AS
BEGIN
--DECLARE  @FileId varchar(15)= 203000619, @siDoctor int=98;
	DECLARE @MedicalID nvarchar(10)='', @DoctorName nvarchar(50)='';

	SELECT @MedicalID= MedicalID, @DoctorName=RTRIM(CONCAT(FNAME,' ',LName)) FROM VW_Default_Doctors_ALL WHERE siDoctors =@siDoctor


	UPDATE NovinTebnegarPatients
	SET 
		DoctorName= @DoctorName,
		AutoStatus = 2,
		MedicalID = NULLIF(@MedicalID,''),
		siDoctor = @siDoctor,
		AnswerDate = CASE WHEN  Status = 3 and AnswerDate is not null THEN Getdate() ELSE  AnswerDate END
	WHERE FileID = @FileId
		
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_LinkPatientToNovin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC	[dbo].[USP_SYS_LinkPatientToNovin]( @FileId varchar(15), @fcode varchar(15)) AS
BEGIN
--DECLARE  @FileId varchar(15)= 203000619, @fcode varchar(15)=13954089;
	DECLARE @DoctorName varchar(50), @MedicalID as nvarchar(10), @FileIdRecord int;
 
	SELECT @DoctorName=DoctorName, @MedicalID=MedicalID FROM FilesTable FT
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor
	WHERE FT.FileID = @FileId;
 
	SELECT TOP 1 @FileIdRecord= FileID from NovinTebnegarPatients WHERE FileID = @FileId; 
	IF @FileIdRecord IS NULL
	BEGIN
 
		INSERT INTO  NovinTebnegarPatients
			(FileID, fcode, FName, LName, Phone1, Mobile, SendType, SendStatus, BirthYear, 
			 MiladiDate, ReferDate, DoctorName, MedicalID, Sex, SexTitle, Status,RegisterDate, TelegramStatus)
		SELECT   @FileId, fcode, fFirstName as FName, fLastName as LName,NULL as Phone1,fMobile as Mobile,
				'SendType' = CASE fEmergency WHEN 1 THEN 0 WHEN 0 THEN 1  END,   
				'SendStatus' = CASE fEmergency WHEN 1 THEN N'اورژانس' WHEN 0 THEN N'عادي' END,
				LEFT(fBirthDate,4) BirthYear, 
				CAST(fDateTime as DATE ) as MiladiDate, 
				fAcceptionDate as ReferDate,
				@DoctorName as DoctorName, 
				@MedicalID as MedicalID,
				fSex as Sex,
				'SexTitle' = CASE fSex WHEN 0 THEN N'زن' WHEN 1 THEN N'مرد' END, 			
				CASE 
					WHEN fCancellation=1 THEN  2 -- canceled
					WHEN fCancellation=0 and fPutAnswer=1 THEN  3  -- putAnswered
					ELSE 1 -- not proccessed
				END  as Status,
				fAcceptionDateTime RegisterDate,
				0		
		FROM NovinAcceptation
		WHERE fcode = @fcode 
	END
	ELSE
	BEGIN
		UPDATE	A
		SET
			DoctorName	= @DoctorName, 
			MedicalID	= @MedicalID,
			fCode = @fcode,
			FName= fFirstName, 
			LName=fLastName, 
			Mobile=fMobile, 
			SendType=CASE fEmergency WHEN 1 THEN 0 WHEN 0 THEN 1  END, 
			SendStatus=CASE fEmergency WHEN 1 THEN N'اورژانس' WHEN 0 THEN N'عادي' END, 
			BirthYear=LEFT(fBirthDate,4), 
			MiladiDate=CAST(fDateTime as DATE ),
			ReferDate=fAcceptionDate,
			Sex=fSex,
			SexTitle= CASE fSex WHEN 0 THEN N'زن' WHEN 1 THEN N'مرد' END,
			Status=
				CASE 
					WHEN fCancellation=1 THEN  2 -- canceled
					WHEN fCancellation=0 and fPutAnswer=1 THEN  3  -- putAnswered
					ELSE 1 -- not proccessed
				END,
			RegisterDate=fAcceptionDateTime
		FROM	NovinTebnegarPatients	A
		INNER JOIN NovinAcceptation B ON A.FileID = @FileId AND B.fCode = @fcode
 
	END
 
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_ReCreateAllAddress]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_SYS_ReCreateAllAddress] AS
begin
	-- آدرس هی پزشک را جدا گانه در فیلد آدرس مجود در جدول پزشکان درج میکند
	DECLARE @FileID int
	DECLARE Doc_Cursor CURSOR FOR
		Select FileID From CosmoPatient..DoctorsTable
	OPEN Doc_Cursor
	FETCH NEXT FROM Doc_Cursor into @FileID
	WHILE @@FETCH_STATUS = 0
	BEGIN
	   Exec CosmoPatient..USP_SeperateAddress @FileID	
	   FETCH NEXT FROM Doc_Cursor into @FileID
	END
	CLOSE Doc_Cursor
	DEALLOCATE Doc_Cursor
end




GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_RoutineName]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_SYS_RoutineName]( @RoutineName as varchar(200)) AS
BEGIN
	SELECT ROUTINE_NAME 
	FROM INFORMATION_SCHEMA.ROUTINES
	WHERE ROUTINE_NAME LIKE '%'+@RoutineName+'%'
	ORDER BY ROUTINE_NAME
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_RoutineText]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create     PROCEDURE [dbo].[USP_SYS_RoutineText]( @RoutineName as nvarchar(max) ) AS  
BEGIN
	DECLARE @I INT=1, @Len INT, @Line nvarchar(MAX), @S nvarchar(max) ='',@Pos INT; 
	SELECT  @S = definition   FROM sys.sql_modules  WHERE object_name(object_id) = @RoutineName
	SET @Len = Len(ISNULL(@S,''))
	IF @Len=0 SELECT  @S = @RoutineName, @Len = LEN(@RoutineName)
 
	WHILE 1=1
	BEGIN
		SET @Line ='';
		SET @Pos = Charindex(Char(13)+Char(10), @S)
		IF @Pos =0 
		BEGIN
			PRINT @S
			BREAK
		END
		SET @Line = LEFT(@S,@Pos-1)
		PRINT @Line
		SET @S= STUFF(@S,1,@Pos+1,'')
	END
END
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_RoutineText2]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_SYS_RoutineText2]( @RoutineName as varchar(200)) AS 
BEGIN

	DECLARE @RoutineText as varchar(max)='';
	
	SELECT @RoutineText=@RoutineText+CAST(SC.text as nvarchar(max)) 
	From Syscomments SC 
	INNER JOIN Sysobjects SO ON SC.id = SO.id 
	WHERE SO.name = @RoutineName

	PRINT @RoutineText
END;

 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_RoutineUsed]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[USP_SYS_RoutineUsed]( @RoutineName as varchar(200)) AS
BEGIN
	SELECT SO.name, SC.Text 
	FROM Syscomments SC
	INNER JOIN Sysobjects SO ON SO.id = SC.id
	WHERE text LIKE '%'+@RoutineName+'%';
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_SelectEMailReady]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_SelectEMailReady] AS
BEGIN
	SELECT TOP 1
		siWait,WaitDate,WaitTimeOut,PatientFullName,EMail1,EMail2,LName,DoctorFullName,
		siFiles,AttachedCount, 
		EMailContent= 
			N' پزشک گرامي دکتر  ' +DoctorFullName +CHAR(13)+
			N' مراجعه کننده ' +PatientFullName +
			N' به همراه:  '+ Phone1+ CHAR(13)+
			CASE WHEN ISNULL(Phone2,N'') <>N'' THEN N' به تلفن:  '+ Phone2+ CHAR(13) ELSE N'' END +
			N' در تاريخ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' موضوع: '+ Subject+'   '+
			CASE BEF_AFT WHEN 1 THEN N'بعد از درمان' ELSE N'قبل از درمان' END +CHAR(13)+
			N' با تشکر طب نگار'
			
	FROM
	(
		SELECT 
			WT.siWait, WT.WaitDate, WT.WaitTimeOut, FT.Subject, FT.Bef_Aft, FT.siFiles,
			ISNULL(FT.FName,'') +' '+ ISNULL(FT.LName,'') as PatientFullName,
			FT.Phone1,  NULLIF(FT.Phone2,'') as Phone2,  
			WT.AttachedCount, 
			DT.EMail1, DT.EMail2, DT.LName, ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'') as DoctorFullName
		FROM WaitTable WT 
		INNER JOIN FilesTable FT ON WT.siFiles = FT.siFiles 
		INNER JOIN DoctorsTable DT ON FT.siDoctor = DT.siDoctors
		LEFT JOIN TblDate WD ON WD.Shamsi = WaitDate  
		LEFT JOIN TblDate Today ON Today.Miladi = Convert(varchar(25),GetDate(),111)   
		WHERE (status = 16) and (SentEMail in( 1) ) AND (IsActiveEMail=1)
		--AND (Today.id-WD.Id)<=(Select	TOP 1 EMailDays From ConfigTable)
	) Tbl
	
END
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_SelectEMailReadyTest]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_SelectEMailReadyTest] AS
BEGIN
	SELECT TOP 1
		siWait,WaitDate,WaitTimeOut,PatientFullName,EMail1,EMail2,LName,DoctorFullName,
		siFiles,AttachedCount, 
		EMailContent=  
			N' پزشک گرامي دکتر  '+DoctorFullName +CHAR(13)+
			N' مراجعه کننده ' +PatientFullName  +
			N' به همراه:  '+ Phone1+ CHAR(13)+
			CASE WHEN ISNULL(Phone2,N'') <>N'' THEN N' به تلفن:  '+ Phone2+ CHAR(13) ELSE N'' END +
			N' در تاريخ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' موضوع: '+ Subject+N'   '+
			CASE BEF_AFT WHEN 1 THEN N'بعد از درمان' ELSE N'قبل از درمان' END +CHAR(13)+
			N' با تشکر طب نگار'
			
	FROM
	(
		SELECT 
			WT.siWait, WT.WaitDate, WT.WaitTimeOut, FT.Subject, FT.Bef_Aft, FT.siFiles,
			ISNULL(FT.FName,'') +' '+ ISNULL(FT.LName,'') as PatientFullName,
			FT.Phone1,  
			NULLIF(FT.Phone2,'') as Phone2,  
			WT.AttachedCount, 
			DT.EMail1, DT.EMail2, DT.LName, ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'') as DoctorFullName
		FROM WaitTable WT 
		INNER JOIN FilesTable FT ON WT.siFiles = FT.siFiles 
		INNER JOIN DoctorsTable DT ON FT.siDoctor = DT.siDoctors
		LEFT JOIN TblDate WD ON WD.Shamsi = WaitDate  
		LEFT JOIN TblDate Today ON Today.Miladi = Convert(varchar(25),GetDate(),111)   
		WHERE (status = 16) --and (SentEMail = 1) AND (IsActiveEMail=1)
		and FT.siFiles = 549108
		--AND (Today.id-WD.Id)<=(Select	TOP 1 EMailDays From ConfigTable)
	) Tbl

END
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_SelectSMSReady]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_SelectSMSReady] AS
BEGIN
	SELECT TOP 1
		siWait,WaitDate,WaitTimeOut,SentSMSTime,PatientFullName,SMS1,SMS2,LName,DoctorFullName,
		SMSContent= 
			N' پزشک گرامي ' +CHAR(13)+
			N' دکتر ' +DoctorFullName +CHAR(13)+
			N' مراجعه کننده ' +PatientFullName +CHAR(13)+
			N' به همراه:  '+ Phone1+ CHAR(13)+
			CASE WHEN ISNULL(Phone2,'') <>'' THEN N' به تلفن:  '+ Phone2+ CHAR(13) ELSE N'' END +
			N' در تاريخ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' موضوع: '+ Subject+CHAR(13)+
			N' در طب نگار پذيرش شد'+CHAR(13)+'با تشکر'
	FROM
	(
		SELECT 
			WT.siWait, WT.WaitDate, WT.WaitTimeOut, WT.SentSMSTime, FT.Subject,
			ISNULL(FT.FName,'') +' '+ ISNULL(FT.LName,'') as PatientFullName,
			FT.Phone1,  NULLIF(FT.Phone2,'') as Phone2, 
			DT.SMS1, DT.SMS2, DT.LName, ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'') as DoctorFullName
		FROM WaitTable WT 
		INNER JOIN FilesTable FT ON WT.siFiles = FT.siFiles 
		INNER JOIN DoctorsTable DT ON FT.siDoctor = DT.siDoctors
		LEFT JOIN TblDate WD ON WD.Shamsi = WaitDate  
		LEFT JOIN TblDate Today ON Today.Miladi = Convert(varchar(25),GetDate(),111)   
		WHERE 
		(status = 16) and (IsActiveSMS=1) AND (SentSMS IS NULL OR SentSMS = 3 ) AND 
		(
		(DATEDIFF(MINUTE, Cast(WaitTimeOut as Time),Cast( Convert(varchar(5),GetDate(),108) as Time))) >( Select DelaySendSMS From ConfigTable)
		OR	(WD.Miladi <> Convert(varchar(25),GetDate(),111) )
		)
		AND (Today.id-WD.Id)<=(Select SMSExpireDay From ConfigTable)
	) Tbl
 
END
 
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_SendTelegram_Automatic]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_SendTelegram_Automatic] AS
BEGIN
	BEGIN TRY	DROP TABLE #TEMP	END TRY BEGIN CATCH END CATCH	
	DECLARE @Date nvarchar(10)= dbo.FN_Today(), @Done int=0;
	DECLARE @FromDate nvarchar(10);
	
	SELECT @FromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 TelegramDays from ConfigTable), MiladiDate) )
	FROM TblDate A 
	WHERE A.Shamsi = @Date
	 
	;WITH CTE AS
	(
	SELECT 
		TP.FileID, 
		fCode, 
		TP.FName, 
		TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, 
		AnswerDate,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName, 
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,
		Status, TelegramStatus, TP.SendDate,
		TP.SendType,
		'SendStatus' = 
			CASE TP.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf')	
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	)	
	SELECT
		RW= ROW_NUMBER() OVER(ORDER BY AnswerDate),SendDate, ISNULL(DATEDIFF(Minute, SendDate,GETDATE()),999) as TelegramLastTryTime, 
		FileID,fCode,FName,LName,FullName,FullName2,Mobile,MiladiDate,AnswerDate,SendDateS,SendTime,
		ReferDate,ReferTime,DoctorName,DoctorName2,Status,TelegramStatus,SendType,SendStatus,
		TelegStatusTitle,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork
	INTO #TEMP
	FROM CTE	
	WHERE	Status >0 and 
		(DATEDIFF(MINUTE, AnswerDate, GETDATE() )) > ( Select NovinDelayTelegram From ConfigTable)
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, 
		Status desc,
		ReferDate DESC , 
		SendType, 
		ReferTime;
 
	DECLARE @I int=1, @CNT int=0, @Status int, @TelegramStatus int, @FileID int, @LastTime int;
	SELECT @CNT=COUNT(*) FROM #TEMP;
	WHILE @I <=@CNT
	BEGIN
		SELECT @Status=Status, @TelegramStatus=ISNULL(TelegramStatus,0), @FileID=FileID, @LastTime= TelegramLastTryTime FROM #TEMP WHERE RW = @I;
		IF @Status<>1 and @TelegramStatus<>1 and @LastTime>=5  
			EXEC USP_Set_Telegram @FileId ,0
		SET @I = @I +1;
	END;
	BEGIN TRY	DROP TABLE #TEMP	END TRY BEGIN CATCH END CATCH	
 
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_SendTelegram_Automatic_OLD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_SendTelegram_Automatic_OLD] AS
BEGIN
	BEGIN TRY	DROP TABLE #TEMP	END TRY BEGIN CATCH END CATCH	
	DECLARE @Date nvarchar(10)= dbo.FN_Today(), @Done int=0;
	DECLARE @FromDate nvarchar(10);
	
	SELECT @FromDate=dbo.FN_DateToShamsi (DateAdd(Day, -(Select Top 1 TelegramDays from ConfigTable), MiladiDate) )
	FROM TblDate A 
	WHERE A.Shamsi = @Date
	 
	;WITH CTE AS
	(
	SELECT 
		TP.FileID, fCode, TP.FName, TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, 
		AnswerDate,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName,
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,		 
		Status, TelegramStatus, TP.SendDate,
		FT.SendType,
		'SendStatus' = 
			CASE FT.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf')	
	FROM NovinTebnegarPatients TP
	INNER JOIN FilesTable FT ON FT.FileID = TP.FileID
	INNER JOIN DoctorsTable DT ON DT.siDoctors = FT.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	UNION
 
	SELECT 
		TP.FileID, 
		fCode, 
		TP.FName, 
		TP.LName, 
		concat(TP.FName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.LName collate SQL_Latin1_General_CP1256_CI_AS) FullName,
		concat(TP.LName  collate SQL_Latin1_General_CP1256_CI_AS,' ',TP.FName collate SQL_Latin1_General_CP1256_CI_AS) FullName2,
		Mobile, TP.MiladiDate, 
		AnswerDate,
		'SendDateS'= TD1.Shamsi ,
		'SendTime'= CAST( CONVERT( Time, SendDate, 111) as nvarchar(5)),
		'ReferDate'= TD2.Shamsi , 
		'ReferTime'= CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5)),
		TP.DoctorName, 
		RTRIM(CONCAT(DT.LName,' ',DT.FName)) as DoctorName2,
		Status, TelegramStatus, TP.SendDate,
		TP.SendType,
		'SendStatus' = 
			CASE TP.SendType           
				WHEN 0 THEN 'اورژانس'           
				WHEN 1 THEN 'عادي'           
			END,   
		'TelegStatusTitle'=
		CASE ISNULL(TelegramStatus,0)
			WHEN	0	THEN N''
			WHEN	1	THEN N'صف ارسال'
			WHEN	2	THEN N'ارسال موفق'
			WHEN	3	THEN N'فايل يافت نشد'
			WHEN	4	THEN N''
			WHEN	5	THEN N'خطا در ارسال'
		END,
		TelegMessageId, TelegramLab, ISNULL(TryCount,0) TryCount,
		PdfPath = CONCAT((Select Top 1 NovinPDFPath From ConfigTable),fCode,'.pdf'),
		PdfNetwork = CONCAT((Select Top 1 NovinPDFNetwork From ConfigTable),fCode,'.pdf')	
	FROM NovinTebnegarPatients TP
	INNER JOIN DoctorsTable DT ON DT.siDoctors = TP.siDoctor
	INNER JOIN TblDate TD2 ON TD2.Miladi = CAST( RegisterDate as DATE)
	LEFT JOIN TblDate TD1 ON TD1.Miladi = CAST( SendDate as DATE)
	WHERE 
		TD2.Shamsi between @FromDate and  @Date and
		( @Done =1 OR ISNULL(TelegramStatus,0) <> 2) and 
		fCode IS NOT NULL and 
		IsActiveTelegLab = 1 and -- آيا تلگرام فعال است
		TelegramLab IS NOT NULL and -- آيا شماره تلگرام دارد
		status in(1,3)
			-- 0: با بارکد پذيرش نشده است    
			-- 1: با بارکد پذيرش شده است    
			-- 2: کنسل شده
			-- 3: جايگذاري شده			
	)	
	SELECT
		RW= ROW_NUMBER() OVER(ORDER BY AnswerDate),SendDate, ISNULL(DATEDIFF(Minute, SendDate,GETDATE()),999) as TelegramLastTryTime, 
		FileID,fCode,FName,LName,FullName,FullName2,Mobile,MiladiDate,AnswerDate,SendDateS,SendTime,
		ReferDate,ReferTime,DoctorName,DoctorName2,Status,TelegramStatus,SendType,SendStatus,
		TelegStatusTitle,TelegMessageId,TelegramLab,TryCount,PdfPath,PdfNetwork
	INTO #TEMP
	FROM CTE	
	WHERE	Status >0 and 
		(DATEDIFF(MINUTE, AnswerDate, GETDATE() )) > ( Select NovinDelayTelegram From ConfigTable)
	ORDER BY  
		CASE WHEN ISNULL(TelegramStatus,0) >=3 THEN NULL ELSE ISNULL(TelegramStatus,0) END, 
		Status desc,
		ReferDate DESC , 
		SendType, 
		ReferTime;
 
	DECLARE @I int=1, @CNT int=0, @Status int, @TelegramStatus int, @FileID int, @LastTime int;
	SELECT @CNT=COUNT(*) FROM #TEMP;
	WHILE @I <=@CNT
	BEGIN
		SELECT @Status=Status, @TelegramStatus=ISNULL(TelegramStatus,0), @FileID=FileID, @LastTime= TelegramLastTryTime FROM #TEMP WHERE RW = @I;
		IF @Status<>1 and @TelegramStatus<>1 and @LastTime>=5  
			EXEC USP_Set_Telegram @FileId ,0
		SET @I = @I +1;
	END;
	BEGIN TRY	DROP TABLE #TEMP	END TRY BEGIN CATCH END CATCH	
 
END;
 
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_Sync]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [dbo].[USP_SYS_Sync] AS        
begin        
 -- لیست پزشکان موجود در دیتابیس پزشکان را در جدول پزشکان در دیتا بیس بیماران کپی می کند        
 Insert into CosmoPatient..DoctorsTable(  FileID, FName, LName, Job, Comment,PerDiscount,SumAfter,FolderName,MedicalID,IsTebDoc)        
 Select         
   FileID, FName, LName, Job, Comment, PerDiscount,SumAfter,FolderName,MedicalID,IsTebDoc        
 From  CosmoDoc..FilesTable        
 where CosmoDoc..FilesTable.FileID not in (Select FileID From CosmoPatient..DoctorsTable)        
 ----------------------------------------        
 EXEC CosmoDoc..USP_SYS_UpdateAllDoctorRecord        
end        

GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_Sync_PSDTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_SYS_Sync_PSDTable] AS
BEGIN
	INSERT INTO PSDTable (siDoctors , Doctor, HasName1, HasName2, HasNameAfter1, HasNameAfter2 )
	SELECT siDoctors, Concat(LName ,ISNULL(' '+ FName,''),'-',Job,'-',FileID ) as Doctor,0,0,0,0 
	FROM DoctorsTable 
	WHERE siDoctors not in ( SELECT siDoctors FROM PSDTable ) and FileID <> 0
END
GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_UpdateAllDoctorRecord]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_SYS_UpdateAllDoctorRecord] AS
begin
	DECLARE @FileID int
	DECLARE Doc_Cursor CURSOR FOR
		Select FileID From CosmoDoc..FilesTable
	OPEN Doc_Cursor
	FETCH NEXT FROM Doc_Cursor into @FileID
	WHILE @@FETCH_STATUS = 0
	BEGIN
	   Exec CosmoPatient..USP_SYS_UpdateDoctorRecord @FileID	
	   Exec CosmoPatient..USP_SeperateAddress @FileID	
	   FETCH NEXT FROM Doc_Cursor into @FileID
	END
	CLOSE Doc_Cursor
	DEALLOCATE Doc_Cursor

end;



GO

/****** Object:  StoredProcedure [dbo].[USP_SYS_UpdateDoctorRecord]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_SYS_UpdateDoctorRecord]( @FileID int) AS          
BEGIN      
 Update CosmoPatient..DoctorsTable          
   Set          
  CosmoPatient..DoctorsTable.FName =  D.FName ,          
  CosmoPatient..DoctorsTable.LName =  D.LName ,          
  CosmoPatient..DoctorsTable.Job =  D.Job ,          
  CosmoPatient..DoctorsTable.Comment =  D.Comment,          
  CosmoPatient..DoctorsTable.PerDiscount =  D.PerDiscount,          
  CosmoPatient..DoctorsTable.SumAfter =  D.SumAfter,          
  CosmoPatient..DoctorsTable.MedicalID =  D.MedicalID,          
  CosmoPatient..DoctorsTable.IsTebDoc =  D.IsTebDoc,          
  CosmoPatient..DoctorsTable.FolderName =  D.FolderName ,         
  CosmoPatient..DoctorsTable.Description =  D.Description          
 FROM CosmoPatient..DoctorsTable P           
  inner join CosmoDoc..FilesTable D ON P.FileId = D.FileID          
 Where P.FileID = @FileID          
END         
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_AccountTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Update_AccountTable](
	@siAccount int,@siFiles int,@siDiscount int,@HosDiscount int,@PerDiscount int,@AfterPrice int,@PhotoPrice int,@TebPrice int,@Discount int,@TotalPrice int,@PayableFee int,@PaidAmount int,@RemainAmount int,@RoundAmount int,@PaidDate varchar(10),@Type tinyint, @Comment varchar(500)) AS 
Begin 
 Update AccountTable
 SET
	siFiles=@siFiles,siDiscount=@siDiscount,PerDiscount=@PerDiscount,Discount=@Discount,TotalPrice=@TotalPrice,PayableFee=@PayableFee,
	PaidAmount=@PaidAmount,RemainAmount=@RemainAmount,RoundAmount=@RoundAmount, PaidDate=@PaidDate  ,Type=@Type,Comment = @Comment
 Where siAccount = @siAccount
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_AccountTable_PaidDate]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
Create PROC [dbo].[USP_Update_AccountTable_PaidDate](@siAccount int, @PaidDate varchar(10), @Comment varchar(500) ) AS
Begin
	update AccountTable
		Set PaidDate = @PaidDate,Comment = @Comment
	Where siAccount = @siAccount  
end;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_AlbumSurgTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_Update_AlbumSurgTable](
	@siAlbumSurg int,@siAlbum int,@siSurgery int) AS 
Begin 
 Update AlbumSurgTable
 SET
	siAlbum=@siAlbum,siSurgery=@siSurgery
 Where siAlbumSurg = @siAlbumSurg
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Update_AlbumTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Update_AlbumTable](  
 @siAlbum int, @siFiles int,@AlbumName varchar(50),@AlbumDate varchar(10), 
 @SurgDate varchar(10), @Comment varchar(200), @AssurList varchar(200), @Remain int ) AS   
Begin   
 Update AlbumTable  
 SET  
	 siFiles=@siFiles, AlbumName=@AlbumName, AlbumDate=@AlbumDate, SurgDate=@SurgDate, Comment=@Comment ,
	 AssurList = @AssurList , Remain=@Remain
 Where siAlbum = @siAlbum  
End;  
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_BoxInfoTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Update_BoxInfoTable](
	@siBoxInfo int,@siPage int,@Grp int,@Type int,@Xmargin int,@Ymargin int,@Status int) AS 
Begin 
 Update BoxInfoTable
 SET
	siPage=@siPage,Grp=@Grp,Type=@Type,Xmargin=@Xmargin,Ymargin=@Ymargin,Status=@Status
 Where siBoxInfo = @siBoxInfo
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Update_CommonTariffTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Update_CommonTariffTable](
	@siCommonTariff  int,@TariffName varchar(50),@Price int,@Type tinyint,@IsAfter tinyint,@Countable tinyint,@Comment varchar(200)) AS 
Begin 
 Update CommonTariffTable
 SET
	TariffName=@TariffName,Price=@Price,Type=@Type,IsAfter=@IsAfter,Countable=@Countable,Comment=@Comment
 Where siCommonTariff = @siCommonTariff
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DeletedFilesTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_DeletedFilesTable](@FileID int, @Status int) AS
BEGIN
	if exists( Select * from  DeletedFilesTable where FileID = @FileID )
		UPDATE	DeletedFilesTable
		SET		Status = @Status , LogDate= GETDATE()
		WHERE FileID = @FileID
	else
		INSERT INTO DeletedFilesTable(FileID,Status,LogDate)
		VALUES(@FileID, @Status, GETDATE() ) 
		
END;

GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DeletedOthersTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_DeletedOthersTable](@FileID int, @Status int) AS
BEGIN
	if EXISTS( Select * from  DeletedOthersTable where FileID = @FileID )
		UPDATE	DeletedOthersTable
		SET		Status = @Status , LogDate= GETDATE()
		WHERE FileID = @FileID
	else
		INSERT INTO DeletedOthersTable(FileID,Status,LogDate)
		VALUES(@FileID, @Status, GETDATE() ) 
		
END;

GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DenseCount_3DWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[USP_Update_DenseCount_3DWait](@siFiles int,@DenseCount int, @Comment nvarchar(500)) AS
Begin
	UPDATE Wait3DTable SET DenseCount =@DenseCount, comment2 =@Comment
	WHERE siFiles=@siFiles
end
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DoctorsTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-----------------------------------------------------

Create Proc [dbo].[USP_Update_DoctorsTable](
	@siDoctors  int,@FileID int,@FName varchar(15),@LName varchar(25),@Job varchar(50),@Address1 varchar(200),@Address2 varchar(200),@Address3 varchar(200),@Address4 varchar(200),@Comment varchar(4000),@Tag1 int,@Tag2 int,@Tag3 int,@Tag4 int) AS 
Begin 
 Update DoctorsTable
 SET
	FileID=@FileID,FName=@FName,LName=@LName,Job=@Job,Address1=@Address1,Address2=@Address2,Address3=@Address3,Address4=@Address4,Comment=@Comment,Tag1=@Tag1,Tag2=@Tag2,Tag3=@Tag3,Tag4=@Tag4
 Where siDoctors = @siDoctors
End;

GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DocumentTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









CREATE Proc [dbo].[USP_Update_DocumentTable](
	@siDocument int,@siAlbum int,@TypeNumber int,@Title varchar(50),@DocumentDate varchar(10),@Path varchar(200),@SumCode int, @PathOrDoc int,@Comment varchar(200)) AS 
Begin 
 Update DocumentTable
 SET
	siAlbum=@siAlbum,TypeNumber=@TypeNumber,Title=@Title,DocumentDate=@DocumentDate,Path=@Path,SumCode=@SumCode,PathOrDoc=@PathOrDoc,Comment =@Comment 
 Where siDocument = @siDocument
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Update_DocumentTable_Check]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Proc [dbo].[USP_Update_DocumentTable_Check](
	@siDocument int,@siAlbum int,@Title varchar(50),@Comment varchar(200),@siPage int, @CheckValue varchar(100) ) AS
Begin 
 Update DocumentTable
 SET
	siAlbum=@siAlbum,
	Title=@Title,
	Comment=@Comment,
	siPage=@siPage,
	CheckValue=@CheckValue	
 Where siDocument = @siDocument
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Update_EMailLab_Novin]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Update_EMailLab_Novin](@FileID int, @Status int ) as
begin
	update NovinTebnegarPatients 
		Set SentEMailLab = @Status, SentEMailLabTime = Getdate() 
	Where FileID = @FileID
end
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Files_Document]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









Create Proc [dbo].[USP_Update_Files_Document]( @siDocument int, @SumCode bigint,@Document Image =NULL ) AS
Begin
  Update DocumentTable
      Set 
	 SumCode = @SumCode ,
	Document = @Document 
  Where siDocument = @siDocument
End









GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Files_Thumb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO









CREATE Proc [dbo].[USP_Update_Files_Thumb]( @siFiles int, @Thumb Image =NULL ) AS
Begin
  Update FilesTable
      Set Thumb = @Thumb 
  Where siFiles = @siFiles
End








GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Files_Used_Surgery]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-- EXEC USP_Update_listOfSurgeryForAllFiles_String      
CREATE Proc [dbo].[USP_Update_Files_Used_Surgery]( @siSurgery int) AS        
BEGIN        
    
  DECLARE @siFiles INT    
  DECLARE Files_cursor CURSOR FOR  
		  SELECT   DISTINCT     
		   FT.siFiles
		  FROM    FilesTable  FT       
		  INNER JOIN  AlbumTable ALT ON FT.siFiles = ALT.siFiles       
		  INNER JOIN  AlbumSurgTable AST ON ALT.siAlbum = AST.siAlbum       
		  WHERE AST.siSurgery = @siSurgery      

   
  OPEN Files_cursor    
  FETCH NEXT FROM Files_cursor INTO @siFiles     
  WHILE @@FETCH_STATUS = 0    
  BEGIN    
    EXEC USP_Insert_listOfSurgeryByFile_String  @siFiles    
    FETCH NEXT FROM Files_cursor INTO @siFiles     
  END    
    
  CLOSE Files_cursor    
  DEALLOCATE Files_cursor    
    
END      




GO

/****** Object:  StoredProcedure [dbo].[USP_Update_FilesTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE Proc [dbo].[USP_Update_FilesTable](        
 @siFiles int,@FileID int,@FName varchar(15),@LName varchar(25),@Phone1 varchar(20),@Phone2 varchar(20),@RefPlace varchar(100),@PaidAfter int,@BirthYear varchar(4),@ReferDate varchar(10), @Subject varchar(200),@Comment varchar(4000),  
 @Address  varchar(200),@Age int ,@SendType int ,@DoctorName varchar(50),@Job varchar(50), @siDoctor int,@RefFileID int ,@siHospital int, @Bef_Aft tinyint,@Sex tinyint ) AS         
Begin         
  Update FilesTable        
  SET        
	  FileID=@FileID, FName=@FName, LName=@LName, Phone1=@Phone1,Phone2=@Phone2, RefPlace = @RefPlace, PaidAfter = @PaidAfter, BirthYear=@BirthYear, ReferDate=@ReferDate,  Subject=@Subject, Comment=@Comment,   
  Address =@Address, Age=@Age, SendType=@SendType, DoctorName=@DoctorName, Job=@Job ,siDoctor=@siDoctor,RefFileID = @RefFileID, siHospital=@siHospital ,Bef_Aft=@Bef_Aft ,Sex = @Sex 
  Where siFiles = @siFiles        
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_FilesTable_FilterList]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_FilesTable_FilterList](@siFiles int)  AS
BEGIN
 
 	IF EXISTS(Select 1  from VW_Select_ListOfFilesWithForbidenSurgery Where siFiles= @siFiles )
		UPDATE FilesTable SET HasFilterList=1 WHERE siFiles= @siFiles
	ELSE
		UPDATE FilesTable SET HasFilterList=NULL WHERE siFiles= @siFiles
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_FilesTable_PaidAfter]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
CREATE Proc [dbo].[USP_Update_FilesTable_PaidAfter]( @siFiles int, @PaidAfter int ) AS           
Begin           
  Update FilesTable          
  SET          
	PaidAfter = @PaidAfter
  Where siFiles = @siFiles          
End
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_FilesTable_ScanStatus]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_FilesTable_ScanStatus](@siFiles int, @IsScanned int ) AS
BEGIN
	Update FilesTable
		SET IsScanned= ISNULL(@IsScanned,-1)
	WHERE siFiles=@siFiles
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_FilesTableOfSurgeryBy_String]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO








CREATE Proc [dbo].[USP_Update_FilesTableOfSurgeryBy_String]( @siFiles int, @Subject varchar(200) ) AS    
BEGIN    
  Update FilesTable
  SET
	Subject= @Subject
  Where siFiles = @siFiles
    
END






GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Icon_Thumb]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE Proc [dbo].[USP_Update_Icon_Thumb]( @siIcon int, @IconThumb Image = NULL ) AS
Begin
  Update IconTable
      Set IconThumb = @IconThumb 
  Where siIcon = @siIcon
End









GO

/****** Object:  StoredProcedure [dbo].[USP_Update_listOfSurgeryForAllFiles_String]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








-- EXEC USP_Update_listOfSurgeryForAllFiles_String  
CREATE Proc [dbo].[USP_Update_listOfSurgeryForAllFiles_String] AS    
BEGIN    

	DECLARE @siFiles INT
	DECLARE Files_cursor CURSOR FOR
	SELECT siFiles FROM FilesTable 

	OPEN Files_cursor
	FETCH NEXT FROM Files_cursor INTO @siFiles 
	WHILE @@FETCH_STATUS = 0
	BEGIN
	   EXEC USP_Insert_listOfSurgeryByFile_String  @siFiles
	   FETCH NEXT FROM Files_cursor INTO @siFiles 
	END

	CLOSE Files_cursor
	DEALLOCATE Files_cursor

END    









GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Manual_Telegram]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_Manual_Telegram]( @siWait int ) AS
BEGIN
	UPDATE WaitTable
	SET 
	    ManualTelegDate= DateAdd(Minute,(Select Top 1  1-TebDelayTelegram FROM ConfigTable),GetDate()),
		ManualTelegStatus = 1,
		TryCount= 0,
		TelegMessageId = NULL
	WHERE siWait = @siWait  
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_ObjectCount_3DWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[USP_Update_ObjectCount_3DWait](@siFiles int,@ObjectCount int, @Comment nvarchar(500)) AS
Begin
	UPDATE Wait3DTable SET ObjectCount =@ObjectCount, comment3 =@Comment
	WHERE siFiles=@siFiles
end
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_PageTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-----------------------------------------------------

Create Proc [dbo].[USP_Update_PageTable](
	@siPage int,@CheckCount int,@TitlePage varchar(200),@PagePhoto image) AS 
Begin 
 Update PageTable
 SET
	CheckCount=@CheckCount,TitlePage=@TitlePage,PagePhoto=@PagePhoto
 Where siPage = @siPage
End;



GO

/****** Object:  StoredProcedure [dbo].[USP_Update_ServiceTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Update_ServiceTable](
	@siServiceTable  int,@siFiles int,@siWait int,@siCommonTariff int,@Number int ,@Type tinyint) AS 
Begin 
 Update ServiceTable
 SET
	siFiles=@siFiles ,siWait =@siWait,siCommonTariff=@siCommonTariff,Number=@Number,Type=@Type
 Where siServiceTable = @siServiceTable
End;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_ShotCount_3DWait]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[USP_Update_ShotCount_3DWait](@siFiles int,@ShotCount int, @Comment nvarchar(500)) AS
Begin
	UPDATE Wait3DTable SET ShotCount =@ShotCount, comment =@Comment
	WHERE siFiles=@siFiles
end
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_SurgeryTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_Update_SurgeryTable](
	@siSurgery int,@SurgeryName varchar(50),@LatinName varchar(50),@Sequent int,@Show varchar(1)='1') AS 
Begin 
 Update SurgeryTable
 SET
	SurgeryName=@SurgeryName,LatinName =@LatinName,Sequent=@Sequent,Show=@Show
 Where siSurgery = @siSurgery
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Update_TelegramStatus]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_TelegramStatus]( @FileID int,@TelegramStatus int,@TelegMessageId int) AS
BEGIN
	UPDATE NovinTebnegarPatients
	SET 
		TelegramStatus= @TelegramStatus, 
		TelegMessageId = @TelegMessageId, 
		TryCount= ISNULL(TryCount,0)+1,
		SendDate = GetDate()
	WHERE FileID = @FileID  
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_TypesTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO









CREATE Proc [dbo].[USP_Update_TypesTable](
	@siTypes int,@Number int, @Type varchar(15)) AS 
Begin 
 Update TypesTable
 SET
	Number =@Number,
	Type=@Type
 Where siTypes = @siTypes
End;







GO

/****** Object:  StoredProcedure [dbo].[USP_Update_UserPassword]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








Create proc [dbo].[USP_Update_UserPassword]( @siUser int, @NewPass varchar(20) ) AS
 UPDATE 
   UserTable
   SET  [Password]= @NewPass
 Where siUser = @siUser








GO

/****** Object:  StoredProcedure [dbo].[USP_Update_Wait_TelegramStatus]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_Wait_TelegramStatus]( @siWait int,@TelegramStatus int,@TelegMessageId int, @AttachedCount int) AS
BEGIN
	DECLARE @ManualTelegDate  Datetime;
	Select @ManualTelegDate = ManualTelegDate  From WaitTable Where siWait = @siWait  

	IF @ManualTelegDate IS NOT NULL -- Manual
	BEGIN
		UPDATE WaitTable
			SET 
				ManualTelegStatus= @TelegramStatus, 
				TelegMessageId = IIF( ISNULL(@TelegMessageId,0) =0,TelegMessageId, @TelegMessageId),  
				TryCount = IIF(@TelegramStatus=1, TryCount, ISNULL(TryCount,0)+1 ),
				ManualTelegDate = GetDate(),
				AttachedCountTeleg = @AttachedCount
		WHERE siWait = @siWait  
	END
	ELSE
	BEGIN  -- Auto
		UPDATE WaitTable
			SET 
				TelegramStatus= @TelegramStatus, 
				TelegMessageId = IIF( ISNULL(@TelegMessageId,0) =0,TelegMessageId, @TelegMessageId),  
				TryCount = IIF(@TelegramStatus=1, TryCount, ISNULL(TryCount,0)+1 ),
				SendDate = GetDate(),
				AttachedCountTeleg = @AttachedCount
		WHERE siWait = @siWait  
	END
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Update_WaitTable](
	@siWait  int,@siFiles int,@WaitDate varchar(10),@WaitTime varchar(5),@SurgStatus tinyint,@Status tinyint,@Comment varchar(500)) AS 
Begin 
 IF ISNULL(@WaitTime,'') = '' 
	 Update WaitTable
	 SET				
		siFiles=@siFiles,WaitDate=@WaitDate,SurgStatus=@SurgStatus,Comment=@Comment
	 Where siWait = @siWait
 ELSE					
	 Update WaitTable
	 SET										
		siFiles=@siFiles,WaitDate=@WaitDate,WaitTime=@WaitTime,SurgStatus=@SurgStatus,Status=@Status,Comment=@Comment
	 Where siWait = @siWait
 
End;


GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Call]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Update_WaitTable_Call](@siWait  int, @WaitCall varchar(5),@MachineDesc varchar(100) ) AS   
Begin  
 if Exists( Select 1 From WaitTable where siWait = @siWait and WaitCall IS NULL )
	 Update WaitTable  -- Before Photo
	 SET            
		WaitCall=@WaitCall,MachinePhoto = @MachineDesc   
	 Where siWait = @siWait    
End;  
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Check]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   Proc [dbo].[USP_Update_WaitTable_Check](@siWait  int, @WaitCheck varchar(5),@MachineDesc varchar(100) )  AS   
Begin  
 
	--IF EXISTS( Select 1 From WaitTable where siWait = @siWait and WaitCheck IS NULL )
		Update WaitTable  -- Before Check
		SET            
			WaitCheck=@WaitCheck,MachineCheck = @MachineDesc   
		Where siWait = @siWait and  WaitCheck IS NULL 
 
End
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Edited]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_WaitTable_Edited](@siWait int, @Edited int) AS
BEGIN
	UPDATE WaitTable
		SET Edited = @Edited
	WHERE siWait = @siWait
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_ForExit]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_WaitTable_ForExit](@siWait  int, @TimeOut varchar(5) = NULL ) AS   
BEGIN   
 Update WaitTable  
 SET            
   WaitTimeOut = @TimeOut  
 Where siWait = @siWait  
   
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Photo]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

  
CREATE Proc [dbo].[USP_Update_WaitTable_Photo](@siWait  int, @WaitPhoto varchar(5) ) AS   
Begin   
 if Exists( Select 1 From WaitTable where siWait = @siWait and WaitPhoto IS NULL )
	 Update WaitTable  -- Photo
	 SET            
	 WaitPhoto=@WaitPhoto  
	 Where siWait = @siWait    
End;  
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Printed]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_Update_WaitTable_Printed](@siWait int, @Printed int) AS
BEGIN
	UPDATE WaitTable
		SET Printed = @Printed
	WHERE siWait = @siWait
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_SendEMail]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_WaitTable_SendEMail]( @siWait int, @SentEMail int, @AttachedCount int ) AS
BEGIN   
  
  DECLARE @EMailDate varchar(10), @EMailTime varchar(5);
  DECLARE @Telegram int=NULL;
  
  Select @EMailDate=Shamsi from TblDate Where  MiladiDate = CAST( GETDATE() as DATE);
  Select @EMailTime= LEFT(CONVERT( nvarchar(10),GetDate() ,108),5);

  Select @Telegram = COUNT(*)
  from DoctorsTable DT
  INNER JOIN FilesTable FT ON FT.siDoctor  = DT.siDoctors 
  INNER JOIN WaitTable WT ON WT.siFiles = FT.siFiles 
  WHERE 
    siWait = @siWait  AND 
    IsActiveTelegTeb = 1 AND  
    TelegramTeb IS NOT NULL AND
    ISNULL(IsAuto,0) =1  AND
    @SentEMail = 3   AND
 ISNULL(HasFilterList,0) = 0
   
    UPDATE WaitTable 
      SET 
        SentEMail = @SentEMail,
        AttachedCount=  CASE WHEN @SentEMail =0 THEN NULL ELSE @AttachedCount END,
        EMailDate =    CASE WHEN @SentEMail =0 THEN NULL WHEN @SentEMail in(2,3) THEN @EMailDate ELSE EMailDate END,
        EMailTime =    CASE WHEN @SentEMail =0 THEN NULL WHEN @SentEMail in(2,3) THEN @EMailTime ELSE EMailTime END,
        TelegramStatus = IIF( @Telegram <> 0 , 1,TelegramStatus),
        SendDate = IIF( @Telegram <>0 , GetDate() ,SendDate),
        AttachedCountTeleg = IIF( @Telegram <>0 , 0,AttachedCountTeleg)
    WHERE siWait = @siWait

END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_SentSMS]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_WaitTable_SentSMS]( @siWait Integer, @SentSMS Integer, @SMSTime DateTime ) AS
BEGIN
	Update WaitTable
		SET 
			SentSMS = @SentSMS,
			SentSMSTime= @SMSTime
	Where siWait = @siWait
END;

GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Service]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Update_WaitTable_Service](@siWait  int, @WaitService varchar(5) ) AS   
Begin   
 if Exists( Select 1 From WaitTable where siWait = @siWait and WaitService IS NULL )
	 Update WaitTable  -- Service
	 SET            
	 WaitService=@WaitService  
	 Where siWait = @siWait    
End;  
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Status]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[USP_Update_WaitTable_Status]( @siWait  int, @Status tinyint ) AS 
BEGIN 
 Declare @siFile int;
 Update WaitTable
 SET										
	Status= @Status,
	WaitCheck = Case when @Status in (1) then NULL else WaitCheck end,
	MachineCheck = Case when @Status in (1) then NULL else MachineCheck end,

	WaitCall = Case when @Status in (2) then NULL else WaitCall end,
	MachinePhoto = Case when @Status in (2) then NULL else MachinePhoto end
 Where siWait = @siWait
 
 SELECT  @siFile = siFiles From WaitTable Where siWait = @siWait

 IF @Status = 16 and EXISTS ( Select * from Wait3DTable Where siFiles = @siFile and  Status<16)
    EXEC USP_Set3DWait_Status  @siFile, 16
 
END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_Status_ByFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROC [dbo].[USP_Update_WaitTable_Status_ByFile]( @siFiles int, @SurgStatus tinyint ) AS 
BEGIN 

     -- 1  'ثبت شد'           
     -- 2  'چک شد'           
     -- 4  'عکسبرداري شد'           
     -- 8  'خدمات تعيين شد'           
     --16  'تسويه حساب شد'           
 Update WaitTable
  SET										
  	SurgStatus=@SurgStatus
 Where siFiles = @siFiles AND Status <> 8 -- امورات انجام شد

END;
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_SurgStatus_ByFile]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


----------------------------------------------------------------------------------
CREATE proc [dbo].[USP_Update_WaitTable_SurgStatus_ByFile]( @siFiles int, @SurgStatus tinyint ) as
BEGIN
	Declare @siWait int
	Select @siWait = siWait From WaitTable Where siFiles = @siFiles
	if ISNULL(@siWait,0) <> 0
		update WaitTable 
			Set SurgStatus = @SurgStatus
		Where siWait=@siWait			
END
GO

/****** Object:  StoredProcedure [dbo].[USP_Update_WaitTable_TimeOut]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Proc [dbo].[USP_Update_WaitTable_TimeOut](@siWait  int, @WaitTimeOut varchar(5) ) AS 
Begin 
 Update WaitTable
 SET										
	WaitTimeOut=@WaitTimeOut
 Where siWait = @siWait
 
End;



GO

/****** Object:  StoredProcedure [sms].[SendSMSReadyByMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE Procedure [sms].[SendSMSReadyByMagfa] AS
BEGIN
	Declare 
		@I int =1,
		@CNT INT =0,
		@siWait int, 
		@SMS nvarchar(100), 
		@SMSContent nvarchar(4000) ,	
		@TrackingNumber nvarchar(4000) ,
		@ErrorMessage	nvarchar(4000) 
	BEGIN TRY DROP TABLE #TEMP END TRY BEGIN CATCH END CATCH
	
	Select RowNO =ROW_NUMBER() OVER( ORDER BY siWait) , siWait, SMS, SMSContent INTO #TEMP from sms.FN_SYS_SelectSMSReadyMagfa( 100 ) 
	
	SELECT @CNT = COUNT(*) FROM #TEMP
 
	WHILE @I <= @CNT 
	BEGIN
		
		SELECT @TrackingNumber=NULL,@ErrorMessage = NULL, @siWait=0, @SMS ='', @SMSContent =''
	
		Select @siWait= siWait, @SMS = SMS, @SMSContent= SMSContent from #TEMP WHERE RowNO = @I
	
		EXEC sms.sp_SendSMS  @SMS, @SMSContent,2,@TrackingNumber out, @ErrorMessage out
 
		--SELECT @TrackingNumber, @ErrorMessage
 
		IF CAST(@TrackingNumber as BIGINT)> 1000 
			UPDATE WaitTable SET
				SentSMS = 1,
				SentSMSTime = CAST( GetDate()  as DATE ) 
			WHERE siWait = @siWait
 
		SET @I = @I +1
	END
END
GO

/****** Object:  StoredProcedure [sms].[SendSMSReadyFreeLABByMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

Create Procedure [sms].[SendSMSReadyFreeLABByMagfa] AS
BEGIN
	Declare 
		@I int =1,
		@CNT INT =0,
		@FileID int, 
		@SMS nvarchar(100), 
		@SMSContent nvarchar(4000) ,	
		@TrackingNumber nvarchar(4000) ,
		@ErrorMessage	nvarchar(4000) 
	BEGIN TRY DROP TABLE #TEMP END TRY BEGIN CATCH END CATCH
	
	Select RowNO =ROW_NUMBER() OVER( ORDER BY FileID) , FileID, SMS, SMSContent INTO #TEMP from sms.FN_SYS_SelectSMSReadyForDeviceFreeLABMagfa( 100 ) 
	
	SELECT @CNT = COUNT(*) FROM #TEMP

	WHILE @I <= @CNT 
	BEGIN
		
		SELECT @TrackingNumber=NULL,@ErrorMessage = NULL, @FileID=0, @SMS ='', @SMSContent =''
	
		Select @FileID= FileID, @SMS = SMS, @SMSContent= SMSContent from #TEMP WHERE RowNO = @I
	
		EXEC sms.sp_SendSMS  @SMS, @SMSContent,2,@TrackingNumber out, @ErrorMessage out

		--SELECT @TrackingNumber, @ErrorMessage

		IF CAST(@TrackingNumber as BIGINT)> 1000 
			UPDATE NovinTebnegarPatients SET
				SentSMS = 1,
				SentSMSTime = CAST( GetDate()  as DATE ) 
			WHERE FileID = @FileID

		SET @I = @I +1
	END
END
GO

/****** Object:  StoredProcedure [sms].[SendSMSReadyLABByMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

Create Procedure [sms].[SendSMSReadyLABByMagfa] AS
BEGIN
	Declare 
		@I int =1,
		@CNT INT =0,
		@siWait int, 
		@SMS nvarchar(100), 
		@SMSContent nvarchar(4000) ,	
		@TrackingNumber nvarchar(4000) ,
		@ErrorMessage	nvarchar(4000) 
	BEGIN TRY DROP TABLE #TEMP END TRY BEGIN CATCH END CATCH
	
	Select RowNO =ROW_NUMBER() OVER( ORDER BY siWait) , siWait, SMS, SMSContent INTO #TEMP from sms.FN_SYS_SelectSMSReadyForDeviceLABMagfa( 100 ) 
	
	SELECT @CNT = COUNT(*) FROM #TEMP

	WHILE @I <= @CNT 
	BEGIN
		
		SELECT @TrackingNumber=NULL,@ErrorMessage = NULL, @siWait=0, @SMS ='', @SMSContent =''
	
		Select @siWait= siWait, @SMS = SMS, @SMSContent= SMSContent from #TEMP WHERE RowNO = @I
	
		EXEC sms.sp_SendSMS  @SMS, @SMSContent,2,@TrackingNumber out, @ErrorMessage out

		--SELECT @TrackingNumber, @ErrorMessage

		IF CAST(@TrackingNumber as BIGINT)> 1000 
			UPDATE [CosmoPatient].dbo.WaitTable SET
				SentSMSLAB = 1,
				SentSMSTimeLAB = CAST( GetDate()  as DATE ) 
			WHERE siWait = @siWait

		SET @I = @I +1
	END
END
GO

/****** Object:  StoredProcedure [sms].[sp_InvokeWebServiceAdv]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [sms].[sp_InvokeWebServiceAdv]
      @URI varchar(2000) = '', 
      @methodName varchar(50) = 'POST',  
      @requestBody varchar(max) = '',  
      @SoapAction varchar(255)='send',  
      @UserNameName nvarchar(100)=NULL, -- Domain\UserNameName or UserNameName  
      @Password nvarchar(100)=NULL  ,
	  @responseText varchar(8000) output
AS 
BEGIN 
	SET NOCOUNT ON 	
 
	--if CharIndex('billingservice/CrmService.php?wsdl',@URI,0)>0	delete from olds.dbo.PartakWSResult;
 
	declare @ShowReport bit = 0  , @ShowError bit = 0;
	IF @methodName = '' 
	BEGIN 
		select FailPoint = 'Method Name must be set' 
		return 
	END 	
	set   @responseText = 'FAILED'
	DECLARE @objectID int 
	DECLARE @hResult int 
	DECLARE @source varchar(255), @desc varchar(255)  
	EXEC @hResult = sp_OACreate 'MSXML2.ServerXMLHTTP', @objectID OUT 
	IF @hResult <> 0  
	BEGIN 
		EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		If @ShowError =1
			SELECT      hResult = convert(varbinary(4), @hResult),  
					source = @source,  
					description = @desc,  
					FailPoint = 'Create failed',  
					MedthodName = @methodName  
			SET @responseText = @desc
		goto destroy  
		return 
	END 
	-- open the destination URI with Specified method  
	EXEC @hResult = sp_OAMethod @objectID, 'open', null, @methodName, @URI, 'false', @UserNameName, @Password 
	IF @hResult <> 0  
	BEGIN 
		  EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		  If @ShowError =1
		  SELECT      
				hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'Open failed',  
				MedthodName = @methodName  
			SET @responseText = @desc
		  goto destroy  
		  return 
	END 
	
	  -- open the destination URI with Specified method 			
	  EXEC @hResult = sp_OAMethod @objectID, 'setOption', null, 2, 13056 			
	  IF @hResult <> 0 			
	  BEGIN 			
			EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 			
  				If @ShowError =1
				SELECT      hResult = convert(varbinary(4), @hResult), 			
							  source = @source, 			
							  description = @desc, 			
							  FailPoint = 'Option failed', 			
							  MedthodName = @methodName 			
				SET @responseText = @desc
				goto destroy 			
				return 			
	  END 
	      
	-- set request headers  
	EXEC @hResult = sp_OAMethod @objectID, 'setRequestHeader', null, 'Content-Type', 'text/xml;charset=UTF-8' 
	IF @hResult <> 0  
	BEGIN 
		EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		If @ShowError =1
		SELECT      
				hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'SetRequestHeader failed',  
				MedthodName = @methodName  
			SET @responseText = @desc
		  goto destroy  
		  return 
	END 
	-- set soap action  
	if @SoapAction <> '' 
	begin 
		EXEC @hResult = sp_OAMethod @objectID, 'setRequestHeader', null, 'SOAPAction', @SoapAction  
		IF @hResult <> 0  
		BEGIN 
			  EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
			  If @ShowError =1
			  SELECT      hResult = convert(varbinary(4), @hResult),  
					source = @source,  
					description = @desc,  
					FailPoint = 'SetRequestHeader failed',  
					MedthodName = @methodName  
				SET @responseText = @desc
			  goto destroy  
			  return 
		END 
	end; 
	
	declare @len int 
	
	set @len = len(@requestBody)  
	
	EXEC @hResult = sp_OAMethod @objectID, 'setRequestHeader', null, 'Content-Length', @len  
	IF @hResult <> 0  
	BEGIN 
		  EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		  If @ShowError =1
		  SELECT      hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'SetRequestHeader failed',  
				MedthodName = @methodName  
			SET @responseText = @desc
		  goto destroy  
		  return 
	END 
 
	-- send the request
	EXEC @hResult   =   sp_OASetProperty   @objectID,'setTimeouts','500000','500000','500000','500000'
	
	IF    @hResult <> 0  
	BEGIN 
		  EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		  If @ShowError =1
		  SELECT      hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'Send failed',  
				MedthodName = @methodName  
			SET @responseText = @desc
		  goto destroy  
		  return 
	END 	  
	
	EXEC @hResult = sp_OAMethod @objectID, 'send', null, @requestBody  
	
	IF    @hResult <> 0  
	BEGIN 
		  EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		  if @ShowError =1
		  SELECT      
				hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'Send failed',  
				MedthodName = @methodName  
		
			SET @responseText= @desc
 
		  goto destroy  
		  return 
	END 
	declare @statusText varchar(1000), @status varchar(1000)  
	-- Get status text  
	--/* 
	exec sp_OAGetProperty @objectID, 'StatusText', @statusText out 
	exec sp_OAGetProperty @objectID, 'Status', @status out 
	if @ShowReport = 1  
		select @status, @statusText, @methodName  
	
	EXEC sp_OAGetProperty @objectID, 'responseText', @responseText out ;
 
	IF @hResult <> 0  
	BEGIN 
		EXEC sp_OAGetErrorInfo @objectID, @source OUT, @desc OUT 
		If @ShowError =1
		SELECT
				hResult = convert(varbinary(4), @hResult),  
				source = @source,  
				description = @desc,  
				FailPoint = 'ResponseText failed',  
				MedthodName = @methodName  
			SET @responseText = @desc
		  goto destroy  
		  return 
	END 
	destroy:  
		  exec sp_OADestroy @objectID  
	SET NOCOUNT OFF 
END; 
GO

/****** Object:  StoredProcedure [sms].[sp_SendSMS]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE     PROCEDURE [sms].[sp_SendSMS]
			( 
			@TelReceiver nvarchar(200), 
			@Body nvarchar(max) ,
			@ProfileID int,
			@TrackingNumber nvarchar(4000) OUT,
			@ErrorMessage	nvarchar(4000) OUT 
			)
AS
BEGIN
	DECLARE @TRCNumber nvarchar(4000)='', @TraceMessage nvarchar(4000) ;
	DECLARE @RetCodeItem  nvarchar(Max)='', @RetCodeFaultString nvarchar(Max)='', @XML XML;
	DECLARE @SenderNumber nvarchar(50) ,@UserName nvarchar(50) , @Password nvarchar(50), @Domain nvarchar(50), @URL nvarchar(500);
	
	SELECT TOP 1  
		@SenderNumber= SenderNumber , @UserName= UserName , @Password= Password, @Domain= Domain, @URL= URL 
	FROM sms.SMSSetting 
	WHERE ID = @ProfileID
 
	IF @ProfileID =2 -- Magfa
	BEGIN 
		EXEC sms.sp_SendSMSByMagfa @Body, @TelReceiver, @TraceMessage OUT 
		SET @TrackingNumber= @TraceMessage
		--PRINT @TraceMessage
		SELECT @XML = CAST( (REPLACE(@TrackingNumber, 'encoding="UTF-8"?','encoding="UTF-16"?')) as XML )
		;WITH CTE AS ( SELECT TOP 1 fld.value('.','nvarchar(4000)') as RetCode from @XML.nodes('//*/item')Tbl(fld) ORDER BY 1 DESC )
		SELECT @RetCodeItem	= RetCode FROM CTE  

		SELECT @RetCodeFaultString = fld.value('.','nvarchar(4000)') from @XML.nodes('//*/faultstring')Tbl(fld)		
		SELECT 
			@TrackingNumber = LTRIM(RTRIM(LEFT(ISNULL(@RetCodeItem , ''),4000 ))), 
			@ErrorMessage   = LTRIM(RTRIM(LEFT(ISNULL(@RetCodeFaultString , '') ,4000)))
		IF TRY_PARSE(@TrackingNumber as bigint) IS NULL 
			SELECT @TrackingNumber = '0', @ErrorMessage   = @TraceMessage

	END
END
GO

/****** Object:  StoredProcedure [sms].[sp_SendSMSByMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [sms].[sp_SendSMSByMagfa]
	@MessageBody nvarchar(MAX) ='Hello!' ,
	@RecieverNumber varchar(max),
	@TrackingNumber nvarchar(MAX) out 
AS
BEGIN
	set transaction isolation level read uncommitted
	begin try
		declare 
			@RecieverList varchar(max)='',
			@Domain varchar(100) ,
			@SenderNumber varchar(10) ,
			@UserName nvarchar(100),
			@Password nvarchar(100),			
			@URL nvarchar(500);
			--select * from dbo.SMSSetting
		
		Select @RecieverList= @RecieverList+Char(10)+Concat('<Item>',Item,'</Item>') 
		from dbo.FN_StringToTable_Not_NULL(@RecieverNumber,',') 
		--Print @RecieverList
		
		select 
			@SenderNumber =SenderNumber , @Domain =Domain ,@UserName = UserName , @URL = URL ,@Password=Password 
		FROM sms.SMSSetting 
		where IsDefault =1 
		declare @ResponseText nvarchar(max)=''
		set @TrackingNumber=null;
		declare @Param nvarchar(max)='<?xml version="1.0" encoding="utf-8"?>
			<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:tns="http://magfa.com/soap/SOAPSmsQueue" xmlns:types="http://magfa.com/soap/SOAPSmsQueue/encodedTypes" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
			  <soap:Body soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
				 <tns:enqueue>
				  <domain xsi:type="xsd:string">'+@Domain+'</domain>
				  <messageBodies href="#id1" />
				  <recipientNumbers href="#id2" />
				  <senderNumbers href="#id3" />
				  <encodings href="#id4" />
				  <udhs href="#id5" />
				  <messageClasses href="#id6" />
				  <priorities href="#id7" />
				  <checkingMessageIds href="#id8" />
				</tns:enqueue>
				<soapenc:Array id="id1" soapenc:arrayType="xsd:string[1]">
				  <Item>'+@MessageBody+'</Item>
				</soapenc:Array>
				<soapenc:Array id="id2" soapenc:arrayType="xsd:string[1]">'
				+@RecieverList+
				'</soapenc:Array>
				<soapenc:Array id="id3" soapenc:arrayType="xsd:string[1]">
				  <Item>'+@senderNumber+'</Item>
				</soapenc:Array>
				<soapenc:Array id="id4" soapenc:arrayType="xsd:int[1]">
				  <Item>0</Item>
				</soapenc:Array>
				<soapenc:Array id="id5" soapenc:arrayType="xsd:string[1]">
				  <Item />
				</soapenc:Array>
				<soapenc:Array id="id6" soapenc:arrayType="xsd:int[1]">
				  <Item>1</Item>
				</soapenc:Array>
				<soapenc:Array id="id7" soapenc:arrayType="xsd:int[1]">
				  <Item>0</Item>
				</soapenc:Array>
				<soapenc:Array id="id8" soapenc:arrayType="xsd:long[1]">
				  <Item>0</Item>
				</soapenc:Array>
			  </soap:Body>
			</soap:Envelope>'
 
		exec sms.sp_InvokeWebServiceAdv
		@URL,
		'POST',
		@Param,
		'enqueue',
		@UserName,
		@Password,
		@ResponseText out					
		set @TrackingNumber= @ResponseText;		
	end try
	begin catch
		select 'There was an error1 !'+ERROR_MESSAGE() as error
	end catch
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_SelectSMSReadyForDeviceFreeLABMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [sms].[USP_SYS_SelectSMSReadyForDeviceFreeLABMagfa]( @Top int ) AS
BEGIN
	Select RowNO =ROW_NUMBER() OVER( ORDER BY FileID),FileID, SMS, SMSContent 
	from [sms].[FN_SYS_SelectSMSReadyForDeviceFreeLABMagfa](100) 
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_SelectSMSReadyForDeviceLABMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [sms].[USP_SYS_SelectSMSReadyForDeviceLABMagfa]( @Top int ) AS
BEGIN
	Select RowNO =ROW_NUMBER() OVER( ORDER BY siWait),siWait, SMS, SMSContent 
	from [sms].[FN_SYS_SelectSMSReadyForDeviceLABMagfa](100) 
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_SelectSMSReadyMagfa]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [sms].[USP_SYS_SelectSMSReadyMagfa]( @Top int ) AS
BEGIN
	Select RowNO =ROW_NUMBER() OVER( ORDER BY siWait),siWait, SMS, SMSContent 
	from [sms].[FN_SYS_SelectSMSReadyMagfa](100) 
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_Update_NovinTebnegarPatients]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [sms].[USP_SYS_Update_NovinTebnegarPatients]( @FileID int ) AS
BEGIN
		UPDATE NovinTebnegarPatients SET
			SentSMS = 1,
			SentSMSTime = CAST( GetDate()  as DATE ) 
		WHERE FileID = @FileID
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_Update_WaitTable]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [sms].[USP_SYS_Update_WaitTable]( @siWait int ) AS
BEGIN
	UPDATE WaitTable SET
		SentSMS = 1,
		SentSMSTime = CAST( GetDate()  as DATE ) 
	WHERE siWait = @siWait
END
GO

/****** Object:  StoredProcedure [sms].[USP_SYS_Update_WaitTableLAB]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [sms].[USP_SYS_Update_WaitTableLAB]( @siWait int ) AS
BEGIN
	UPDATE WaitTable SET
		SentSMSLAB = 1,
		SentSMSTimeLAB = CAST( GetDate()  as DATE ) 
	WHERE siWait = @siWait
END
GO

/****** Object:  StoredProcedure [tools].[RemovePermissionOnFolderHDD]    Script Date: 7/26/2020 2:53:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [tools].[RemovePermissionOnFolderHDD] ( @Days int ) AS
Begin
	Drop table IF EXISTS _tempPermission;
	Create Table _tempPermission(si int, siFile int, Script nvarchar(4000), Status tinyint default 0, ActionTime datetime );
	-- truncate table _tempPermission
	declare @Logins nvarchar(1000) =''
	Select @Logins = @Logins +' '+LoginName from LoginGroup
	
	insert into _tempPermission(siFile , Script,  ActionTime )
	Select 
		distinct siFile, LEFT(ScriptDeny, Charindex('/remove',ScriptDeny)+6)+' '+@Logins+' /T''' as Script, ActionTime  
	from PermissionTable 
	where ActionTime  <=GETDATE() -@Days
	order by ActionTime desc
 
	;With cte as
	(
		Select Row_number() Over(order by sifile ) as RW, si from _tempPermission 
	)
	update cte set si = RW 
	;
 
	declare @i int =1 , @cnt int=0, @si int,@siFile int, @S nvarchar(4000);
	SET NOCOUNT ON;
	DROP TABLE IF EXISTS #TEMP;
	Select IDENTITY(int,1,1) as ID, si ,siFile,Script,Status into #TEMP from _tempPermission WHERE Status =0  
	Select @Cnt = Count(*) from #TEMP 
	WHILE @I <= @cnt 
	BEGIN
		SELECT @si =si, @siFile= siFile , @S= Script FROM #TEMP WHERE ID = @I
		EXEC (@S)
		UPDATE _tempPermission SET Status = 1 WHERE  si = @si
		delete PermissionTable where siFile = @siFile
		--RAISERROR ( @S ,10,1)
		SET @I = @I+1
	END
 
--Select * from #TEMP order by 1 
 
END
GO


