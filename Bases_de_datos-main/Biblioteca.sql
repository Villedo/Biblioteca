use master
if exists (select * from sysdatabases where name='Biblioteca')
	drop database Biblioteca
go
create database Biblioteca
GO
USE Biblioteca
GO

CREATE TABLE Categoria(
    IDcategoria int not null identity(1, 1),
    Nombre varchar(30),
    CONSTRAINT PK_IDcategoria PRIMARY KEY(IDcategoria)
)
 
CREATE TABLE Libros(
    ISBN int not null,
    Titulo varchar(30),
    Autor varchar(30),
    Editorial varchar(30),
    Publicacion date,
    Num_Copias int,
	Estado varchar(10) default 'disponible',
    CONSTRAINT PK_ISBN PRIMARY KEY(ISBN),
)

CREATE TABLE Categoria_Libro(
	IDcategoria int not null,
	ISBN int not null,
	CONSTRAINT PK_Categoria_Libro UNIQUE(IDcategoria, ISBN),
	CONSTRAINT FK_IDcategoria FOREIGN KEY(IDcategoria) REFERENCES Categoria(IDcategoria) ON DELETE CASCADE,
	CONSTRAINT FK_ISBN FOREIGN KEY(ISBN) REFERENCES Libros(ISBN) ON DELETE CASCADE
)

CREATE TABLE Usuarios(
    IDusuario int not null identity (1000, 1),
    Nombre varchar(30),
	Primerapellido varchar(25),
	Segundoapellido varchar(25),
    Direccion varchar(30),
    Telefono varchar(15),
    Correo_electronico varchar(50) not null,
	Cantprest int default 0,
	Membresia bit default 1,
    CONSTRAINT PK_IDusuario PRIMARY KEY(IDusuario),
	CONSTRAINT UC_Correo UNIQUE(Correo_electronico)
)

CREATE TABLE Bibliotecario(
	IDpersonal int not null identity (2000, 1),
	Nombre varchar(50),
	Primerapellido varchar(25),
	Segundoapellido varchar(25),
	Direccion varchar(50),
	Telefono varchar(15),
	Correo_electronico varchar(30)
	CONSTRAINT PK_IDpersonal PRIMARY KEY(IDpersonal)
)

CREATE TABLE Prestamos(
    IDprestamo int not null identity(1,1),
    IDusuario int not null,
    ISBN int not null,
	IDpersonal int not null,
    FechaInicio date,
    FechaFin date,
	Fecharegreso date default null,
    Renovacion bit default 0,
	IDpersonal_renovacion int default null,
    CONSTRAINT PK_IDprestamo PRIMARY KEY(IDprestamo),
    CONSTRAINT FK_IDusuario FOREIGN KEY(IDusuario) REFERENCES Usuarios(IDusuario),
    CONSTRAINT FK_ISBN_prestamo FOREIGN KEY(ISBN) REFERENCES Libros(ISBN),
	CONSTRAINT FK_IDprestamo FOREIGN KEY(IDpersonal) REFERENCES Bibliotecario(IDpersonal),
	CONSTRAINT FK_IDprestamo_renovacion FOREIGN KEY(IDpersonal_renovacion) REFERENCES Bibliotecario(IDpersonal)
)

Create table Reservaciones (
	IDreservacion int not null, 
	IDusuario int not null,
	ISBN int not null,
	Fechareserva date,
	Constraint PK_IDreservacion Primary Key(IDreservacion),
	Constraint FK_IDusuario_reservacion Foreign Key(IDusuario) References Usuarios(IDusuario),
	Constraint FK_ISBN_reservacion Foreign key(ISBN) References Libros(ISBN)
)

Create table Multas (
	IDprestamo int not null,
	IDusuario int not null, 
	Cantidad int,
	Fechamulta date,
	Fechapago date null, 
	Constraint PK_IDmulta Primary Key(IDprestamo, IDusuario),
	Constraint FK_IDprestamo_multa Foreign Key (IDprestamo) References Prestamos(IDprestamo),
	Constraint FK_IDusuarios_multa Foreign Key (IDusuario) References Usuarios(IDusuario)
)

alter table Multas add constraint CH_Prestamo_multas check (Cantidad >= 0)
go
alter table Usuarios add constraint CH_cantidad_prestamos check (Cantprest >= 0 and Cantprest <=5)
go


--Aqui empiezan los triggers
Create Trigger Tr_ActualizarEstadoLibro 
on Prestamos
instead of insert
as 
Begin 
	Declare @ISBN int, @idusuario int
	select @ISBN = ISBN
	from inserted

	select @idusuario = IDusuario
	from inserted

	If (Select Num_Copias From Libros Where ISBN = @ISBN ) > 0
	begin
		Update Libros set Num_Copias = Num_Copias - 1 where ISBN = @ISBN
		insert into Prestamos (IDusuario, ISBN, IDpersonal, FechaInicio, FechaFin)
		select IDusuario, ISBN, IDpersonal, FechaInicio, FechaFin
		from inserted
		if (Select Num_Copias from Libros where ISBN = @ISBN) < 1
		begin 
			Update Libros set Estado = 'No disponible' where ISBN = @ISBN
		end
	end
End
go 

create trigger Tr_CalcularMulta
on Prestamos 
for update
as
begin
    declare @diasPasados int, @idprestamo int, @FechaFin date, @idusuario int
    
    declare cr_prestamos cursor for
        select IDprestamo, FechaFin, IDusuario
        from inserted

    open cr_prestamos
    fetch next from cr_prestamos into @idprestamo, @FechaFin, @idusuario

    while @@FETCH_STATUS = 0
    begin
        set @diasPasados = datediff(day, @FechaFin, GETDATE())

        if @diasPasados > 0
        begin
            insert into Multas (IDprestamo, IDusuario, Cantidad, Fechamulta)
            values (@idprestamo, @idusuario, @diasPasados, GETDATE())
        end

        fetch next from cr_prestamos into @idprestamo, @FechaFin, @idusuario
    end

    close cr_prestamos
    deallocate cr_prestamos
end
go

--Aqui empiezan los Stored Precedures
Create procedure SP_AgregarLibros
@ISBN int, @Titulo varchar(30), @Autor varchar(30), @Editorial varchar(30),@Publicacion date, @Num_Copias int
As 
Begin
	Insert into Libros(ISBN, Titulo,Autor,Editorial,Publicacion,Num_Copias) values (@ISBN, @Titulo,@Autor,@Editorial,@Publicacion,@Num_Copias)
End
go

CREATE PROCEDURE SP_PrestarLibro
    @idusuario INT,
    @ISBN INT,
    @IDpersonal INT
AS
BEGIN
    DECLARE @FechaInicio DATE, @FechaFin DATE, @DiaSemana INT, @HoraActual TIME
    SET @FechaInicio = GETDATE()
    SET @FechaFin = DATEADD(DAY, 14, @FechaInicio)

    -- Obtener el d�a de la semana y la hora actual
    SET @DiaSemana = DATEPART(WEEKDAY, @FechaInicio)
    SET @HoraActual = CONVERT(TIME, GETDATE())

    -- Validar que solo se permita de lunes a viernes de 9:00 a.m. a 6:00 p.m. y s�bados de 10:00 a.m. a 2:00 p.m.
    IF (
           (@DiaSemana >= 2 AND @DiaSemana <= 6 AND @HoraActual BETWEEN '09:00' AND '18:00') 
        OR (@DiaSemana = 7 AND @HoraActual BETWEEN '10:00' AND '14:00')
       )
    BEGIN
        UPDATE Usuarios SET Cantprest = Cantprest + 1 WHERE IDusuario = @idusuario
        INSERT INTO Prestamos (IDusuario, ISBN, IDpersonal, FechaInicio, FechaFin) 
        VALUES (@idusuario, @ISBN, @IDpersonal, @FechaInicio, @FechaFin)
    END
    ELSE
    BEGIN
        RAISERROR('Los registros solo se pueden hacer de lunes a viernes de 9:00 a.m. a 6:00 p.m. y los s�bados de 10:00 a.m. a 2:00 p.m.', 16, 1)
    END
END
GO


Create Procedure SP_RegistrarUsuario 
@Nombre varchar(30),@Primerapellido varchar(25),@Segundoapellido varchar(25),@Direccion varchar(30),@Telefono varchar(15),@Correo_electronico varchar(50) 
As 
Begin 
	Insert into Usuarios (Nombre,Primerapellido,Segundoapellido,Direccion, Telefono, Correo_electronico) Values (@Nombre,@Primerapellido,@Segundoapellido,@Direccion,@Telefono,@Correo_electronico)
End
go

Create Procedure SP_RegistrarPersonal
@Nombre varchar(30),@Primerapellido varchar(25),@Segundoapellido varchar(25),@Direccion varchar(30),@Telefono varchar(15),@Correo_electronico varchar(50) 
As 
Begin 
	Insert into Bibliotecario(Nombre,Primerapellido,Segundoapellido,Direccion, Telefono, Correo_electronico) Values (@Nombre,@Primerapellido,@Segundoapellido,@Direccion,@Telefono,@Correo_electronico)
End
go

Create Procedure SP_DevolverLibro
@idprestamo int
as
begin
	-- Variables para verificar d�a y hora
	declare @diaSemana int = DATEPART(WEEKDAY, GETDATE())
	declare @horaActual time = CONVERT(time, GETDATE())

	-- Comprobar si es dentro del horario permitido
	if (
		(@diaSemana >= 2 and @diaSemana <= 6 and @horaActual >= '09:00' and @horaActual <= '18:00') -- Lunes a viernes de 9 a 18
		or (@diaSemana = 7 and @horaActual >= '10:00' and @horaActual <= '14:00') -- S�bado de 10 a 14
	)
	begin
		-- Validar si el pr�stamo ya tiene una fecha de regreso
		if (select FechaRegreso from Prestamos where IDprestamo = @idprestamo) is null
		begin
			Update Prestamos set FechaRegreso = GETDATE() where IDprestamo = @idprestamo
		end
	end
	else
	begin
		-- Mensaje de error si el registro no es dentro del horario permitido
		raiserror('La devoluci�n solo puede realizarse de lunes a viernes de 9 a 18 horas, y los s�bados de 10 a 14 horas.', 16, 1)
	end
end
go


create procedure SP_RonovarPrestamo
@idprestamo int
as 
begin
	if(select Renovacion from Prestamos where IDprestamo = @idprestamo) = 0
	begin
		update Prestamos set Renovacion = 1, FechaFin = dateadd(day, 14, FechaFin) where IDprestamo = @idprestamo
	end
end
go

Create Procedure Sp_GenerarReporte 
@Year int,  @month int
As 
Begin
	Select IDprestamo,IDusuario,ISBN,IDpersonal,FechaInicio,FechaFin,Fecharegreso
	From Prestamos
	Where YEAR(FechaInicio) = @Year and MONTH(FechaInicio) = @month

	Select IDprestamo,IDusuario,Cantidad,Fechamulta,Fechapago
	From Multas 
	Where YEAR(Fechamulta) = @Year and MONTH(Fechamulta) = @month 

	Select ISBN, Titulo,Autor,Editorial,Num_Copias
	From Libros
End
go

Create Procedure SP_RespaldoBiblioteca 
@backupFilePath varchar(300),
@databaseName varchar(200)
as 
begin
	BACKUP DATABASE @databaseName
	to disk = @backupFilePath
end
go