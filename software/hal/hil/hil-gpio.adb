
with STM32.GPIO;  use STM32.GPIO;
with STM32.Device;

package body HIL.GPIO is

   SPI1_SCK  : constant STM32.GPIO.GPIO_Point := STM32.Device.PA5;
   SPI1_MISO : constant STM32.GPIO.GPIO_Point := STM32.Device.PA6;
   SPI1_MOSI : constant STM32.GPIO.GPIO_Point := STM32.Device.PA7;


   UART2_RX : constant STM32.GPIO.GPIO_Point := STM32.Device.PD6;
   UART2_TX : constant STM32.GPIO.GPIO_Point := STM32.Device.PD5;

   UART3_RX : constant STM32.GPIO.GPIO_Point := STM32.Device.PD9;
   UART3_TX : constant STM32.GPIO.GPIO_Point := STM32.Device.PD8;


   Config_SPI1 : constant GPIO_Port_Configuration := (
         Mode => Mode_AF,
         Output_Type => Push_Pull,
         Speed => Speed_50MHz,
         Resistors => Floating );

   Config_UART3 : constant GPIO_Port_Configuration := (
         Mode => Mode_AF,
         Output_Type => Push_Pull,
         Speed => Speed_50MHz,
         Resistors => Floating );


   function map(Point : GPIO_Point_Type) return GPIO_Point is
      ( case Point is
         when RED_LED     => STM32.Device.PE12,
         when SPI_CS_BARO => STM32.Device.PD7
     );
   -- function map(Signal : GPIO_Signal_Type) return GPIO_Signal_Type;


   procedure write (Point : GPIO_Point_Type; Signal : GPIO_Signal_Type) is
      stm32_point : GPIO_Point := map( Point );
   begin
      case (Signal) is
         when LOW  => STM32.GPIO.Clear( stm32_point  );
         when HIGH => STM32.GPIO.Set( stm32_point  );
      end case;
   end write;


   procedure configure is
      Config_Out : constant GPIO_Port_Configuration := (
         Mode => Mode_Out,
         Output_Type => Push_Pull,
         Speed => Speed_2MHz,
         Resistors => Floating );
       Config_In : constant GPIO_Port_Configuration := (
         Mode => Mode_In,
         Output_Type => Push_Pull,
         Speed => Speed_2MHz,
         Resistors => Floating );
      Point      : GPIO_Point := STM32.Device.PE12;
   begin
      -- configure LED
      Configure_IO( Points => (1 => map(RED_LED)), Config => Config_Out );



      --configure SPI 1
      Configure_IO( Points => (SPI1_SCK, SPI1_MISO, SPI1_MOSI), Config => Config_SPI1 );

      Configure_Alternate_Function(
         Points => (1 => SPI1_SCK, 2 => SPI1_MOSI),
         AF     => GPIO_AF_SPI1);


      -- configure Baro ChipSelect
      Configure_IO( Point => map(SPI_CS_BARO), Config => Config_Out );
      Point := map(SPI_CS_BARO);
      STM32.GPIO.Set( This => Point );

       -- configure UART 3
      Configure_IO( Points => (UART2_RX, UART2_TX), Config => Config_UART3 );

      Configure_Alternate_Function(
         Points => (UART2_RX, UART2_TX),
         AF     => GPIO_AF_USART2);

      -- configure UART 3
      Configure_IO( Points => (UART3_RX, UART3_TX), Config => Config_UART3 );

      Configure_Alternate_Function(
         Points => (UART3_RX, UART3_TX),
         AF     => GPIO_AF_USART3);


   end configure;


--     function map(Point : GPIO_Point_Type) return GPIO_Points is
--     begin
--        case Point is
--        when RED_LED => (Periph => STM32_SVD.GPIO.GPIOE_Periph, Pin => 12);
--        end case;
--     end map;


   -- function map(Signal : GPIO_Signal_Type) return HAL.GPIO.GPIO_Signal_Type
   -- is (case Signal is
   --        when HIGH => HAL.GPIO.HIGH,
   --        when LOW => HAL.GPIO.LOW );



end HIL.GPIO;
