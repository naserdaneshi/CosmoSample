USE [CosmoSample]
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReady]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReady]() RETURNS TABLE AS
RETURN
(

	SELECT 
		siWait,WaitDate,WaitTimeOut,SentSMSTime,PatientFullName,SMS1,SMS2,LName,DoctorFullName,
		PhoneCount= CASE WHEN SMS2 IS NULL THEN 1 ELSE 2 END,
		SMSContent= 
			N'ÿ» ‰ê«—' +CHAR(13)+
			N' Å“‘ò ê—«„Ì ' +CHAR(13)+
			N' œò — ' +DoctorFullName +CHAR(13)+
			N' „—«Ã⁄Â ò‰‰œÂ ' +PatientFullName +CHAR(13)+
			N' »Â Â„—«Â:  '+ Phone1+ CHAR(13)+
			CASE WHEN ISNULL(Phone2,'') <>'' THEN N' »Â  ·›‰:  '+ Phone2+ CHAR(13) ELSE '' END +
			N' œ—  «—ÌŒ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' „Ê÷Ê⁄: '+ Subject+CHAR(13)+
			N' Å–Ì—‘ ‘œ '+CHAR(13)+
			N' »«  ‘ò— '
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
		(status = 16) and (IsActiveSMS=1) AND (SentSMS IS NULL OR SentSMS > 1 ) AND 
		(
		(DATEDIFF(MINUTE, Cast(WaitTimeOut as Time),Cast( Convert(varchar(5),GetDate(),108) as Time))) >( Select DelaySendSMS From ConfigTable)
		OR	(WD.Miladi <> Convert(varchar(25),GetDate(),111) )
		)
		AND (Today.id-WD.Id)<=(Select SMSExpireDay From ConfigTable)
	) Tbl

)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyForDevice]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyForDevice]() RETURNS TABLE AS
RETURN
(
	SELECT 
		siWait, PhoneCount, REPLACE(';'+SMS1,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReady()
	WHERE SMS1 IS NOT NULL
	UNION 
	SELECT 
		siWait, PhoneCount, REPLACE(';'+SMS2,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReady()
	WHERE SMS2 IS NOT NULL 
)

	
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyFreeLAB]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyFreeLAB]() RETURNS TABLE AS RETURN(
	WITH CTE_LAB AS
	(
		SELECT
			TP.FileID, fCode, TP.FName, TP.LName, ISNULL(TP.FName,'') +' '+ ISNULL(TP.LName,'') as PatientFullName,
			Mobile,SendStatus, MiladiDate, SentSMS, 
			TP.ReferDate, TP.DoctorName as DoctorFullName, Status, siDoctor,
			'WaitDate' = dbo.FN_DateToShamsi(RegisterDate),
			'WaitTimeOut'=CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5))
		FROM NovinTebnegarPatients TP
		WHERE Status > 0 and Status <> 2 and ISNULL(AutoStatus,0) in(1,2) AND siDoctor IS NOT NULL
	)
	SELECT 
		FileID,
		SMS1,SMS2,LName,
		PhoneCount= CASE WHEN SMS2 IS NULL THEN 1 ELSE 2 END,
		SMSContent= 
			N'¬“„«Ì‘ê«Â Å« Ê»ÌÊ·ÊéÌ Å«—” ÿ»' +CHAR(13)+
			N' Å“‘ò ê—«„Ì ' +CHAR(13)+
			N' œò — ' +DoctorFullName +CHAR(13)+
			N' „—«Ã⁄Â ò‰‰œÂ ' +PatientFullName +CHAR(13)+
			N' »Â  ·›‰: '+ Mobile+ CHAR(13)+
			N' œ—  «—ÌŒ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' Å–Ì—‘ ‘œ '+CHAR(13)+
			N' »«  ‘ò— '
	FROM
	(
		SELECT 
			LB.FileID,
			LB.WaitDate, 
			LB.WaitTimeOut, 
			PatientFullName,
			Mobile, 
			DT.SMS1, DT.SMS2, 
			DT.LName, 
			DoctorFullName
		FROM CTE_LAB LB  
		INNER JOIN DoctorsTable DT ON LB.siDoctor = DT.siDoctors
		LEFT JOIN TblDate WD ON WD.Shamsi = LB.WaitDate  
		LEFT JOIN TblDate Today ON Today.Miladi = Convert(varchar(25),GetDate(),111)   
		WHERE 
			IsActiveSMS=1 AND 
			ISNULL(SentSMS,0) <>1  AND
			(DATEDIFF(MINUTE, Cast(WaitTimeOut as Time),Cast( Convert(varchar(5),GetDate(),108) as Time))) >( Select NovinDelaySMS From ConfigTable) AND
			(Today.id-WD.Id)<=(Select SMSExpireDay From ConfigTable)
	) Tbl
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyForDeviceFreeLAB]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyForDeviceFreeLAB]() RETURNS TABLE AS
RETURN
(
	SELECT 
		FileID, PhoneCount, REPLACE(';'+SMS1,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyFreeLAB()
	WHERE SMS1 IS NOT NULL
	UNION 
	SELECT 
		FileID, PhoneCount, REPLACE(';'+SMS2,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyFreeLAB()
	WHERE SMS2 IS NOT NULL 
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyForDeviceMagfa]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyForDeviceMagfa]() RETURNS TABLE AS RETURN
(
	SELECT 
		siWait, SMS=  REPLACE(CONCAT(IIF(SMS1 IS NULL,',', SMS1),IIF(SMS2 IS NOT NULL,',',''), SMS2),',,',''), SMSContent
	FROM dbo.FN_SYS_SelectSMSReady()
	WHERE SMS1 IS NOT NULL OR SMS2 IS NOT NULL 
)
GO

/****** Object:  UserDefinedFunction [sms].[FN_SYS_SelectSMSReadyForDeviceFreeLABMagfa]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [sms].[FN_SYS_SelectSMSReadyForDeviceFreeLABMagfa]( @Top int) RETURNS TABLE AS
RETURN
(
	SELECT Top( @Top)
		FileID, SMS=  REPLACE(CONCAT(IIF(SMS1 IS NULL,',', SMS1),IIF(SMS2 IS NOT NULL,',',''), SMS2),',,',''), SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyFreeLAB()
	WHERE SMS1 IS NOT NULL OR SMS2 IS NOT NULL 
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_GetFolderPathForPatient]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_GetFolderPathForPatient](@siFiles int) RETURNS TABLE AS
RETURN
(

	SELECT 
		FT.FileID, FT.FName, FT.LName, FT.PathFolder,
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
	)


GO

/****** Object:  UserDefinedFunction [dbo].[FN_GetFolderPathForPatientNew]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_GetFolderPathForPatientNew](@siFiles int) RETURNS TABLE AS
RETURN
(
 
	SELECT 
		FT.siFiles,
		'Path'= FT.PathFolder+'\'+
				Dc.FolderName+'\'+
				FT.LName+' '+
				FT.FName+' '+ 
				CAST(FT.FileId AS NVARCHAR(200))
	FROM FilesTable FT
	INNER JOIN  DoctorsTable DC  ON Ft.siDoctor = DC.siDoctors
	WHERE FT.siFiles = @siFiles
	)
 
 
 
GO

/****** Object:  UserDefinedFunction [dbo].[FN_LoginHasGrantExceptGroup]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_LoginHasGrantExceptGroup](@siFile int, @LoginName nvarchar(20) ) RETURNS TABLE AS
RETURN
(	
	SELECT DISTINCT LoginName 
	FROM PermissionTable 
	WHERE  
		siFile = @siFile AND  
		Status = 'G' AND
		LoginName NOT IN 
						( 
						SELECT B.LoginName 
						FROM LoginGroup A 
						INNER JOIN LoginGroup B ON A.GroupCode = B.GroupCode and A.LoginName = @LoginName
						) 
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_LoginHasGrantExceptLogin]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   FUNCTION [dbo].[FN_LoginHasGrantExceptLogin](@siFile int, @LoginName nvarchar(20) )  RETURNS TABLE AS
RETURN
(
		SELECT DISTINCT LoginName 
		FROM PermissionTable 
		WHERE  
			siFile = @siFile AND  
			Status = 'G' AND
			LoginName <> @LoginName
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyForDeviceLAB]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyForDeviceLAB]() RETURNS TABLE AS
RETURN
(
	SELECT 
		siWait, PhoneCount, REPLACE(';'+SMS1,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyLAB()
	WHERE SMS1 IS NOT NULL
	UNION 
	SELECT 
		siWait, PhoneCount, REPLACE(';'+SMS2,';0','+98') as SMS, SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyLAB()
	WHERE SMS2 IS NOT NULL 
)
GO

/****** Object:  UserDefinedFunction [dbo].[FN_SYS_SelectSMSReadyLAB_OLD]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_SYS_SelectSMSReadyLAB_OLD]() RETURNS TABLE AS RETURN
(
	WITH CTE_LAB AS
	(
		SELECT
			TP.FileID, fCode, TP.FName, TP.LName , Mobile,SendStatus, MiladiDate, TP.ReferDate, TP.DoctorName, Status, 
			'WaitDate' = dbo.FN_DateToShamsi(RegisterDate),
			'WaitTimeOut'=CAST( CONVERT( Time, RegisterDate, 111) as nvarchar(5))
		FROM NovinTebnegarPatients TP
		WHERE Status > 0 and Status <> 2
	)
	SELECT 
		siWait,SMS1,SMS2,LName,
		PhoneCount= CASE WHEN SMS2 IS NULL THEN 1 ELSE 2 END,
		SMSContent= 
			N'¬“„«Ì‘ê«Â Å« Ê»ÌÊ·ÊéÌ Å«—” ÿ»' +CHAR(13)+
			N' Å“‘ò ê—«„Ì ' +CHAR(13)+
			N' œò — ' +DoctorFullName +CHAR(13)+
			N' „—«Ã⁄Â ò‰‰œÂ ' +PatientFullName +CHAR(13)+
			N' »Â  ·›‰: '+ Phone1+ CHAR(13)+
			N' œ—  «—ÌŒ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' Å–Ì—‘ ‘œ '+CHAR(13)+
			N' »«  ‘ò— '
	FROM
	(
		SELECT 
			WT.siWait, 
			LB.WaitDate, 
			LB.WaitTimeOut, 
			ISNULL(FT.FName,'') +' '+ ISNULL(FT.LName,'') as PatientFullName,
			FT.Phone1, 
			DT.SMS1, DT.SMS2, 
			DT.LName, 
			ISNULL(DT.FName,'') +' '+ ISNULL(DT.LName,'') as DoctorFullName
		FROM WaitTable WT 
		INNER JOIN FilesTable FT ON WT.siFiles = FT.siFiles 
		INNER JOIN CTE_LAB LB ON LB.FileId = FT.FileId 
		INNER JOIN DoctorsTable DT ON FT.siDoctor = DT.siDoctors
		LEFT JOIN TblDate WD ON WD.Shamsi = LB.WaitDate  
		LEFT JOIN TblDate Today ON Today.Miladi = Convert(varchar(25),GetDate(),111)   
		WHERE 
		IsActiveSMS=1 AND 
		SentSMS = 1 AND
		(SentSMSLAB IS NULL OR SentSMSLAB >1 ) AND 
		(Today.id-WD.Id)<=(Select SMSExpireDay From ConfigTable)
	) Tbl
)
 
GO

/****** Object:  UserDefinedFunction [sms].[FN_SYS_SelectSMSReadyForDeviceLABMagfa]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [sms].[FN_SYS_SelectSMSReadyForDeviceLABMagfa]( @Top int) RETURNS TABLE AS
RETURN
(
	SELECT Top( @Top)
		siWait, SMS=  REPLACE(CONCAT(IIF(SMS1 IS NULL,',', SMS1),IIF(SMS2 IS NOT NULL,',',''), SMS2),',,',''), SMSContent
	FROM dbo.FN_SYS_SelectSMSReadyLAB()
	WHERE SMS1 IS NOT NULL OR SMS2 IS NOT NULL 
)
GO

/****** Object:  UserDefinedFunction [sms].[FN_SYS_SelectSMSReadyMagfa]    Script Date: 7/26/2020 2:50:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION  [sms].[FN_SYS_SelectSMSReadyMagfa]( @Top int ) RETURNS TABLE AS RETURN
(
	SELECT TOP (@Top)
		siWait,WaitDate,WaitTimeOut,SentSMSTime,PatientFullName,SMS1,SMS2,LName,DoctorFullName,
		SMS=  REPLACE(CONCAT(IIF(SMS1 IS NULL,',', SMS1),IIF(SMS2 IS NOT NULL,',',''), SMS2),',,',''),
		SMSContent= 
			N' Å“‘ò ê—«„Ì ' +CHAR(13)+
			N' œò — ' +DoctorFullName +CHAR(13)+
			N' „—«Ã⁄Â ò‰‰œÂ ' +PatientFullName +CHAR(13)+
			N' »Â Â„—«Â:  '+ Phone1+ CHAR(13)+
			CASE WHEN ISNULL(Phone2,'') <>'' THEN N' »Â  ·›‰:  '+ Phone2+ CHAR(13) ELSE N'' END +
			N' œ—  «—ÌŒ '+ WaitDate+' - '+WaitTimeOut+	CHAR(13)+
			N' „Ê÷Ê⁄: '+ Subject+CHAR(13)+
			N' œ— ÿ» ‰ê«— Å–Ì—‘ ‘œ'+CHAR(13)+'»«  ‘ò—'
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
)
GO


