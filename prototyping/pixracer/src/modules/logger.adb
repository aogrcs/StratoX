--  Project: StratoX
--  Authors: Emanuel Regnath (emanuel.regnath@tum.de)
--          Martin Becker (becker@rcs.ei.tum.de)
--
--  Description:
--     allows logging of structured messages at several logging levels.
--
--  Usage:
--     Logger.init  -- initializes the Logger
--     Logger.log_console (Logger.INFO, "Program started.") -- write to UART
--     Logger.log_sd (Logger.INFO, gps_msg) -- writes GPS record to SD card
--     Logger.log (Logger.INFO, "hello") -- writes to both SD and console
with System;
with SDLog;
with NVRAM;
with Buildinfo;
with HIL.Devices;
with HIL.UART;
with HIL.Random;
with Interfaces; use Interfaces;
with Ada.Unchecked_Conversion;
with Ada.Real_Time; use Ada.Real_Time;
with Bounded_Image;
with ULog;

--  force elaboration of those before the logging task starts
pragma Elaborate_All (SDLog);
pragma Elaborate_All (Ulog);

--  @summary Simultaneously writes to UART, and SD card.
package body Logger with SPARK_Mode,
  Refined_State => (LogState => (queue_ulog, Logging_Task, logger_level))
is

   --  the type for the queue buffer
   type Buffer_Ulog is array (Natural range <>) of ULog.Message;
   type bufpos is mod LOG_QUEUE_LENGTH;

   --  if GNATprove crashes with reference to that file,
   --  then you have run into bug KP-160-P601-005.
   --  workaround: move decl of protected type to package spec.

   ---------------------
   --  LOG QUEUE TYPE
   ---------------------

   --  protected type to implement the ULog queue
   protected type Ulog_Queue_T is
      procedure Enable;
      --  initially the queue does not accept messages
      --  call this after everything has been set up
      --  (SD log, etc.).

      procedure New_Msg (msg : in ULog.Message);
      --  enqueue new message. this is not blocking, except to ensure mutex.
      --  it is fast (only memcpy), but it can silently fail if buffer is full.
      --  FIXME: how can we specify a precondition on the private variable?
      --  for now we put an assertion in the body

      entry Get_Msg (msg : out ULog.Message; n_queued_before : out Natural)
      with Pre => not msg'Constrained;
      --  try to get new message from buffer. if empty, this is blocking
      --  until buffer has data, and then returns it.
      --  try to get new message from buffer. if empty, this is blocking
      --  until buffer has data, and then returns it.
      --  FIXME: how can we specify a precondition on the private variable?
      --  for now we put an assertion in the body

      function Get_Num_Overflows return Natural;
      --  query how often the buffer overflowed. If this happens, either
      --  increase the buffer QUEUE_LENGTH, or increase priority of the
      --  logger task.

      function Get_Length return Natural;
      --  query number of messages waiting in the logging queue.
   private
      Buffer : Buffer_Ulog (0 .. LOG_QUEUE_LENGTH - 1);
      --  cannot use a discriminant for this (would violate
      --  No_Implicit_Heap_Allocations)

      Queue_Enable  : Boolean := False;
      Num_Queued    : Natural := 0;
      Not_Empty     : Boolean := False; -- simple barrier (Ravenscar)
      Pos_Read      : bufpos := 0;
      Pos_Write     : bufpos := 0;
      Num_Overflows : Natural := 0;
      --  cannot use a dynamic predicate to etablish relationship, because
      --  this requires a record. But we cannot have a record, since this
      --  would make Not_Empty a non-simple barrier (=> Ravenscar violation).
   end Ulog_Queue_T;

   --  sporadic logging task waking up when message is enqueued
   task Logging_Task is
      pragma Priority (System.Priority'First); -- lowest prio for logging
   end Logging_Task;
   pragma Annotate
     (GNATprove, Intentional,
      """sdlog.fh_log"" might not be initialized before start of tasks of type ""Logging_Task""",
      "The queue will not accept values before fh_log is initialized. MBe.");

   ----------------------------
   --  PROTOTYPES
   ----------------------------
   subtype Img_String is String (1 .. 3);
   function Image (level : Log_Level) return Img_String;

   procedure Write_Bytes_To_SD (len : Natural; buf : HIL.Byte_Array)
     with Pre => buf'Last >= buf'First and
     then len <= Natural (Unsigned_16'Last) and
     then buf'Length >= len;

   ----------------------------
   --  INTERNAL STATES
   ----------------------------

   queue_ulog   : Ulog_Queue_T;
   logger_level : Log_Level := DEBUG;

   --------------
   --  LOG TASK
   --------------

   --  the task which logs to SD card in the background
   task body Logging_Task is
      msg    : ULog.Message;
      BUFLEN : constant := 512;
      bytes  : HIL.Byte_Array (1 .. BUFLEN);
      len    : Natural;

      type loginfo_ratio is mod 100;
      r : loginfo_ratio := 0;

      n_que : Natural;
      max_q : Natural := 0; --  max. queue level between queue logs
   begin
      loop
         queue_ulog.Get_Msg (msg, n_que); -- under mutex, must be fast
         ULog.Serialize_Ulog (msg, len, bytes); -- this can be slow again
         Write_Bytes_To_SD (len => len, buf => bytes);

         if n_que > max_q then
            max_q := n_que;
         end if;

         --  occasionally log queue state (overflows, num_queued).
         r := r + 1;
         if r = 0 then
            declare
               m : ULog.Message (ULog.LOG_QUEUE);
               n_ovf : constant Natural := queue_ulog.Get_Num_Overflows;
            begin
               m.t := Ada.Real_Time.Clock;
               if n_ovf > Natural (Unsigned_16'Last) then
                  m.n_overflows := Unsigned_16'Last;
               else
                  m.n_overflows := Unsigned_16 (n_ovf);
               end if;
               if max_q > Natural (Unsigned_8'Last) then
                  m.max_queued := Unsigned_8'Last;
               else
                  m.max_queued := Unsigned_8 (max_q);
               end if;
               if n_que > Natural (Unsigned_8'Last) then
                  m.n_queued := Unsigned_8'Last;
               else
                  m.n_queued := Unsigned_8 (n_que);
               end if;
               ULog.Serialize_Ulog (m, len, bytes);
               Write_Bytes_To_SD (len => len, buf => bytes);
               max_q := 0;
            end;
         end if;
      end loop;
   end Logging_Task;

   --  implementation of the message queue
   protected body Ulog_Queue_T is

      procedure Enable is
      begin
         Queue_Enable := True;
      end Enable;

      procedure New_Msg (msg : in ULog.Message) is
      begin
         if Queue_Enable then
            Buffer (Integer (Pos_Write)) := msg;
            pragma Annotate
              (GNATprove, False_Positive,
               "discriminant check might fail",
               "GNATprove does not see that the buffer consists of mutable variant records. MBe");

            Pos_Write := Pos_Write + 1;
            if Num_Queued < Buffer'Last then
               Num_Queued := Num_Queued + 1;
            else -- =Buffer'Last
               Pos_Read := Pos_Read + 1; -- overwrite oldest
               if Num_Overflows < Natural'Last then
                  Num_Overflows := Num_Overflows + 1;
               end if;
            end if;

            Not_Empty := (Num_Queued > 0);
            pragma Assert ((Not_Empty and (Num_Queued > 0)) or
                             ((not Not_Empty) and (Num_Queued = 0)));
         end if;
      end New_Msg;

      entry Get_Msg (msg             : out ULog.Message;
                     n_queued_before : out Natural) when Not_Empty is
      begin
         pragma Assume (Num_Queued > 0); -- via barrier and assert in New_Msg

         msg := Buffer (Integer (Pos_Read));

         n_queued_before := Num_Queued;
         Pos_Read := Pos_Read + 1;
         Num_Queued := Num_Queued - 1;

         Not_Empty := Num_Queued > 0;
         pragma Assert ((Not_Empty and (Num_Queued > 0)) or
                          ((not Not_Empty) and (Num_Queued = 0)));
      end Get_Msg;

      function Get_Num_Overflows return Natural is (Num_Overflows);
      function Get_Length return Natural is (Num_Queued);
   end Ulog_Queue_T;

   ----------------------------
   --  Instantiation / Body   --
   ----------------------------

   --  slow procedure! Takes Byte_Array, converts to SD data type and writes
   procedure Write_Bytes_To_SD (len : Natural; buf : HIL.Byte_Array) is
   begin
      if len > 0 then
         declare
            pragma Assert (len > 0);
            subtype Bytes_ULog is HIL.Byte_Array (1 .. len);
            up : constant Unsigned_16 := Unsigned_16 (len);
            subtype SD_Data_ULog is SDLog.SDLog_Data (1 .. up);
            function To_FileData is new
              Ada.Unchecked_Conversion (Bytes_ULog, SD_Data_ULog);

            buf_last : constant Integer := buf'First + (len - 1);
            n_wr : Integer;
            pragma Unreferenced (n_wr);
         begin
            if SDLog.Is_Open then -- defensive programming.
               SDLog.Write_Log
                 (To_FileData (buf (buf'First .. buf_last)), n_wr);
            end if;
         end;
      end if;
   end Write_Bytes_To_SD;

   --  HAL, only change Adapter to port Code
   package body Adapter is
      procedure init_adapter (status : out Init_Error_Code) is
      begin
         --  HIL.UART.configure; already done in CPU.initialize
         status := SUCCESS;
      end init_adapter;

      procedure write (message : Message_Type) is
         CR : constant Character := Character'Val (13); -- ASCII
         LF : constant Character := Character'Val (10); -- ASCII
      begin
         if message'Last < Integer'Last - 1 then
            HIL.UART.write
              (HIL.Devices.TELE2, HIL.UART.toData_Type (message & CR & LF));
         else
            --  no space left for CR/LF
            HIL.UART.write
              (HIL.Devices.TELE2, HIL.UART.toData_Type (message));
         end if;
      end write;
   end Adapter;


   --------------
   --  Init
   --------------

   procedure Init (status : out Init_Error_Code) is
   begin
      SDLog.Init;
      Adapter.init_adapter (status);
   end Init;

   -----------
   --  Image
   -----------
   function Image (level : Log_Level) return Img_String is
   begin
      return (case level is
                 when SENSOR => "S: ",
                 when ERROR => "E: ",
                 when WARN  => "W: ",
                 when INFO  => "I: ",
                 when DEBUG => "D: ",
                 when TRACE => "T: ");
   end Image;


   procedure log (msg_level : Log_Level; message : Message_Type) is
      text_msg : ULog.Message (ULog.TEXT);
      now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      maxlen : constant Integer :=
        (if message'Length > text_msg.txt'Length
         then text_msg.txt'Length
         else message'Length);
   begin
      log_console (msg_level, message);
      if maxlen > 0 then
         if Log_Level'Pos (msg_level) <= Log_Level'Pos (INFO) then
            text_msg.t := now;
            declare
               idx_t : constant Integer := text_msg.txt'First - 1 + maxlen;
               idx_m : constant Integer := message'First + (maxlen - 1);
            begin
               text_msg.txt (text_msg.txt'First .. idx_t) :=
                 message (message'First .. idx_m);
               text_msg.txt_last := idx_m;
            end;
            log_sd (msg_level, text_msg);
         end if;
      end if;
   end log;

   -----------------
   --  log_console
   -----------------

   procedure log_console (msg_level : Log_Level; message : Message_Type)
     with SPARK_Mode => Off is
   begin
      if Log_Level'Pos (msg_level) <= Log_Level'Pos (logger_level) then
         Adapter.write (Image (msg_level) & message);
      end if;
   end log_console;

   ----------------
   --  log_sd
   ----------------

   procedure log_sd (msg_level : Log_Level; message : ULog.Message) is
   begin
      if Log_Level'Pos (msg_level) <= Log_Level'Pos (logger_level) then
         queue_ulog.New_Msg (message);
      end if;
   end log_sd;

   -------------------
   --  set_log_level
   -------------------

   procedure Set_Log_Level (level : Log_Level) is
   begin
      logger_level := level;
   end Set_Log_Level;

   -------------------
   --  Start_SDLog
   -------------------

   procedure Start_SDLog is
      num_boots : HIL.Byte;
      rand32 : Unsigned_32;
   begin
      NVRAM.Load (variable => NVRAM.VAR_BOOTCOUNTER, data => num_boots);
      HIL.Random.Get_Unsigned (rand32);
      declare
         buildstring : constant String := Buildinfo.Short_Datetime;
         bootstr     : constant String :=
           Bounded_Image.Unsigned8_Img (num_boots);
         rnd         : constant Unsigned_8 := Unsigned_8 (16#FF# and rand32);
         rndstr      : constant String := Bounded_Image.Unsigned8_Img (rnd);
         fname       : constant String :=
           bootstr (bootstr'First .. bootstr'Last) & "_" & rndstr & ".log";
         BUFLEN      : constant := 128; -- header is around 90 bytes long
         bytes       : HIL.Byte_Array (1 .. BUFLEN);
         len         : Natural;
         valid       : Boolean;
         log_started : Boolean;
      begin
         SDLog.Start_Logfile (dirname  => buildstring,
                              filename => fname,
                              ret      => log_started);
         if not log_started
         then
            log_console
              (Logger.ERROR,
               "Cannot create logfile: " & buildstring & "/" & fname);
         else
            log_console
              (Logger.WARN,
               "Log name: " & buildstring & "/" & fname);

            Get_Ulog_Defs_Loop :
            loop
               ULog.Get_Header_Ulog (bytes, len, valid);
               pragma Annotate (GNATprove, Intentional,
                                """bytes"" might not be initialized", "MBe");

               exit Get_Ulog_Defs_Loop when not valid;
               if len > 0 then
                  Write_Bytes_To_SD (len => len, buf => bytes);
               end if;
            end loop Get_Ulog_Defs_Loop;

            queue_ulog.Enable;
         end if;
      end;

   end Start_SDLog;

end Logger;
