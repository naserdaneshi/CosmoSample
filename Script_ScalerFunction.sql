USE [CosmoSample]
GO

/****** Object:  UserDefinedFunction [dbo].[CountOfChar]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE FUNCTION [dbo].[CountOfChar]( @String nvarchar(1000) , @CHR nvarchar(1)) returns int AS
BEGIN
	Declare @CNT int ,  @I INT , @L INT
	SET @I = 1  
	SET @CNT = 0 
	SET @L = LEN( @String )
	WHILE @I <= @L 
	BEGIN
		IF Substring(@String,@I,1) = @CHR
			SET @CNT = @CNT +1
		SET @I = @I +1	
	END

	RETURN @CNT
END




GO

/****** Object:  UserDefinedFunction [dbo].[CountOfLines]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-----------------------
create function [dbo].[CountOfLines](@S varchar(1000)) returns int as
begin
declare @I int,@L int,@k int, @S1 varchar(1000), @S2 varchar(1000)
Set @i = 0
Set @K = 0
Set @L = Len(@S)
While @I < @L
begin 
	if Substring( @S,@i,1)= Char(10) Set @K = @K +1
	SET @I = @I +1 
end
 return @K
end

GO

/****** Object:  UserDefinedFunction [dbo].[FN_DateToShamsi]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_DateToShamsi]( @SystemDate as datetime ) RETURNS char(10) AS      
BEGIN      
      
DECLARE @Ret AS varchar(10)    
 SET @Ret = NULL  
IF @SystemDate IS NULL   
RETURN(@Ret)  
DECLARE  @I int, @BaseYear int, @DayesPassed int, @DaysForThisYear int      
DECLARE  @Year int, @Month int, @Day int       
DECLARE  @DaysPassedForMonth varchar(60)      
       
  SET @DaysPassedForMonth = '000031062093124155186216246276306336366'      
      
  SELECT @BaseYear = 1, @DayesPassed = Floor( cast(@SystemDate AS decimal(18,6) ))       
  SET @DayesPassed = @DayesPassed + 466702      
  WHILE 1=1      
  BEGIN      
	  if (@BaseYear % 33)  in (1,5,9,13,17,22,26,30)  
	  	  SELECT @DaysForThisYear = 366
	  ELSE
	  	  SELECT @DaysForThisYear = 365
	  	 	  
	  IF @DayesPassed <= @DaysForThisYear BREAK      
	  SELECT @DayesPassed = @DayesPassed - @DaysForThisYear, @BaseYear = @BaseYear +1        
  END           
      
  SELECT @Year = @BaseYear , @I = 1       

  WHILE @I<= 12       
  BEGIN      
	  IF  @DayesPassed <= Cast( substring( @DaysPassedForMonth, @I*3+1 ,3) AS int ) BREAK      
	  SELECT @I = @I +1      
  END      
      
  SELECT @DayesPassed = @DayesPassed - Cast( substring(@DaysPassedForMonth, (@I-1)*3+1 ,3) AS int )      
  SElECT @Month =@I, @Day = @DayesPassed      
      
  SELECT @Ret = Cast( @Year AS varchar(4) )    
  IF @Month <= 9    SET @RET = @Ret +'/0'+ Cast(@Month AS varchar(2)) ELSE   SET @RET = @Ret +'/'+ Cast(@Month AS varchar(2))    
  IF @Day <= 9     SET @RET = @Ret +'/0'+ Cast(@Day AS varchar(2))   ELSE   SET @RET = @Ret +'/'+ Cast(@Day AS varchar(2))    
    
       
 RETURN( @Ret )      
      
END       


GO

/****** Object:  UserDefinedFunction [dbo].[FN_FixLetter]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  FUNCTION [dbo].[FN_FixLetter]( @S varchar(4000) ) Returns nvarchar(100) AS
BEGIN
	RETURN REPLACE(REPLACE( @S , NCHAR(1705), NCHAR(1603)),NCHAR(1740),NCHAR(1610) )
END; 
GO

/****** Object:  UserDefinedFunction [dbo].[FN_FixLetter100]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  FUNCTION [dbo].[FN_FixLetter100]( @S varchar(4000) ) Returns nvarchar(100) AS
BEGIN
	RETURN REPLACE(REPLACE( @S , NCHAR(1705), NCHAR(1603)),NCHAR(1740),NCHAR(1610) )
END; 
GO

/****** Object:  UserDefinedFunction [dbo].[FN_GetNewFileID]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_GetNewFileID]( @siBranch int  ) RETURNS INT  AS
BEGIN 
	DECLARE  @YearCode int, @Ret int;
	Select Top 1 @YearCode= YearCode FROM ConfigTable;
	SELECT @Ret = ISNULL(Max(FileID), @siBranch*100000000+@YearCode*1000000)+1 FROM FilesTable
	Where siBranch =@siBranch
	RETURN @Ret
END
GO

/****** Object:  UserDefinedFunction [dbo].[FN_MiladiToShamsi]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_MiladiToShamsi](@MiladiDate Date) Returns Char(10) AS
BEGIN
	DECLARE @Shamsi Char(10);
	SELECT @Shamsi=Shamsi FROM TblDate
	WHERE MiladiDate = Cast( @MiladiDate as Date );

	Return @Shamsi
END
GO

/****** Object:  UserDefinedFunction [dbo].[FN_ShamsiToMiladi]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_ShamsiToMiladi](@Shamsi Char(10)) Returns Char(10) AS
BEGIN
	DECLARE @Miladi Char(10)='';
	SELECT @Miladi= Miladi FROM TblDate
	WHERE  Shamsi = @Shamsi 
	Return @Miladi
END
GO

/****** Object:  UserDefinedFunction [dbo].[FN_Today]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[FN_Today]() Returns Char(10) AS
BEGIN
	DECLARE @Shamsi Char(10);
	SELECT @Shamsi=Shamsi FROM TblDate WHERE MiladiDate = Cast( Getdate() as Date );

	Return @Shamsi
END
GO

/****** Object:  UserDefinedFunction [dbo].[PatternCheck]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE function [dbo].[PatternCheck]( @Statement varchar(100) , @Pattern varchar(100) , @A_O int) returns int AS
BEGIN

DECLARE @CH varchar(1) , @L int , @I int, @RES int 

SET @L = LEN( @Pattern )
SET @I = 1
-- 0 means And condition ; 1 means OR condition
IF @A_O = 0  SET @RES = 1 ELSE   SET @RES = 0 

WHILE @I <= @L   
BEGIN
	SET @CH = substring( @Pattern ,@I ,1 )
	IF  @CH <> '2' 
	BEGIN
		IF ( @A_O = 1 ) 
		BEGIN
			IF substring( @Statement ,@I ,1 ) = @CH 
			BEGIN
				SET @RES = 1
				BREAK
			END
		END
		ELSE
		BEGIN
			IF substring( @Statement ,@I ,1 ) <> @CH 
			BEGIN
				SET @RES = 0
				Break
			END

		END
	END 
	SET @I = @I +1 
END

RETURN (@RES)

END



GO

/****** Object:  UserDefinedFunction [dbo].[RenameSpecifiedDirectory]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS OFF
GO

SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[RenameSpecifiedDirectory](@src [nvarchar](1000), @dest [nvarchar](1000))
RETURNS [nvarchar](100) WITH EXECUTE AS CALLER
AS 
EXTERNAL NAME [TaffCoCLR].[UserDefinedFunctions].[RenameFolder]
GO

/****** Object:  UserDefinedFunction [tools].[FN_FixWinLetters]    Script Date: 7/26/2020 2:51:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  function [tools].[FN_FixWinLetters]( @S nvarchar(4000) ) Returns nvarchar(4000) AS  
Begin  
 RETURN REPLACE(REPLACE( @S , NCHAR(1603), NCHAR(1705)),NCHAR(1610),NCHAR(1740) )  
End;   
 
GO


