package body p4 with SPARK_MODE is
   -- minimalist evil: line 32 is missed silently, but post is obviosuly stupid
   --function f1 (X : Integer) return Integer is (X) with Post => False;

   -- this is more evil: Post has no failing VC
   -- because a failing VC in the body shadows it
   -- and line 32 is missed
   function f1 (X : Integer) return Integer with
     Pre => X in Integer'Range,
     Post => f1'Result = X + 1
   is
   begin
      return X ;--+ 1;
   end f1;

   -- this is a semi-benign case:
   -- failing VC indicated in Post, so user has to act upon it.
   -- nevertheless, line 32 is missed!
--     function f1 (X : Integer) return Integer with
--       Pre => X in Integer'Range,
--       Post => f1'Result = X + 1
--     is
--     begin
--        return X;
--     end f1;

   --  the following function is needed just to get this faulty program
   --  to compile. Otherwise the compiler detects the overflow and refuses.
   function hide_addition_from_compiler (X : Integer) return Integer is
   begin
      return X + 1; -- this is a guaranteed exception being missed
   end hide_addition_from_compiler;

   procedure foo is
      X : Integer := Integer'Last;
      Z : Integer;
   begin
      Z := X + 1; --hide_addition_from_compiler (X);
      Z := f1(X);
   end foo;
end p4;
