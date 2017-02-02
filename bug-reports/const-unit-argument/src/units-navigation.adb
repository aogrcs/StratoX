with Units; use Units;

package body Units.Navigation with SPARK_Mode is



   --  phi=atan2(sin(delta_lon) * cos (lat2), cos lat1 * sin lat2 - sin lat1 * cos(lat2) * cos (delta_lon)
   function Bearing (source_location : GPS_Loc_Type; target_location  : GPS_Loc_Type) return Heading_Type is
      result : Angle_Type := 0.0 * Degree;
      a1, a2 : Unit_Type;
   begin
      -- calculate angle between -180 .. 180 Degree
      if source_location.Longitude /= target_location.Longitude or
        source_location.Latitude /= target_location.Latitude
      then
         a1 := Sin (delta_Angle (source_location.Longitude, target_location.Longitude)) * Cos (target_location.Latitude);
         declare
            cs  : Unit_Type := Cos (source_location.Latitude) * Sin (target_location.Latitude);
            scc  : Unit_Type := Sin (source_location.Latitude) * Cos(target_location.Latitude);
            cd  : Unit_Type := Cos (delta_Angle (source_location.Longitude, target_location.Longitude));
         begin
            cs := Clip_Unitcircle (cs); -- this really helps the solvers

            scc := Clip_Unitcircle (scc);
            cd  := Clip_Unitcircle (cd);
            scc := scc * cd;
            scc := Clip_Unitcircle (scc);
            a2  := cs - scc;
         end;
         -- SPARK Pro 18.w: error with DEGREE 360; remove "constant" and it works
         result := Arctan (Y => a1, X => a2, Cycle => DEGREE_360);
         -- or like this:
         --result := Arctan (Y => a1, X => a2, Cycle => 360.0 * Degree);
      end if;

      --  shift to Heading_Type
      if result < 0.0 * Degree then
         result := result + Heading_Type'Last;
      end if;
      return Heading_Type( result );
   end Bearing;



   --  From http://www.movable-type.co.uk/scripts/latlong.html
   --  based on the numerically largely stable "haversine"
   --  haversine = sin^2(delta_lat/2) + cos(lat1)*cos(lat2) * sin^2(delta_lon/2)
   --  c = 2 * atan2 (sqrt (haversine), sqrt (1-haversine))
   --  d = EARTH_RADIUS * c
   --  all of the checks below are proven.
   function Distance (source : GPS_Loc_Type; target: GPS_Loc_Type) return Length_Type is
      EPS : constant := 1.0E-12;
      pragma Assert (EPS > Float'Small);

      delta_lat : constant Angle_Type := Angle_Type(target.Latitude) - Angle_Type(source.Latitude);
      delta_lon : constant Angle_Type := Angle_Type(target.Longitude) - Angle_Type(source.Longitude);
      dlat_half : constant Angle_Type := delta_lat / Unit_Type (2.0);
      dlon_half : constant Angle_Type := delta_lon / Unit_Type (2.0);
      haversine : Unit_Type;
      sdlat_half : Unit_Type;
      sdlon_half : Unit_Type;
      coscos : Unit_Type;

   begin
      --  sin^2(dlat/2): avoid underflow
      sdlat_half := Sin (dlat_half);
      --sdlat_half := Clip_Unitcircle (sdlat_half);
      if abs(sdlat_half) > EPS then
         sdlat_half := sdlat_half * sdlat_half;
      else
         sdlat_half := Unit_Type (0.0);
      end if;
      --pragma Assert (Float'Safe_First <= Float (sdlat_half) and Float'Safe_Last >= Float (sdlat_half)); -- OK
      -- clip inaccuracy overshoots, which helps the provers tremendously
      sdlat_half := Clip_Unitcircle (sdlat_half); -- sin*sin should only exceed 1.0 by imprecision: OK

      --  sin^2(dlon/2): avoid underflow
      sdlon_half := Sin (dlon_half);
      --sdlon_half := Clip_Unitcircle (sdlon_half);
      if abs(sdlon_half) > EPS then
         sdlon_half := sdlon_half * sdlon_half;
      else
         sdlon_half := Unit_Type (0.0);
      end if;
      sdlon_half := Clip_Unitcircle (sdlon_half); -- cos*cos should only exceed 1.0 by imprecision: OK

      --  cos*cos
      declare
         cs : constant Unit_Type := Cos (source.Latitude);
         ct : constant Unit_Type := Cos (target.Latitude);
      begin
         --pragma Assert (ct in Unit_Type (-1.0) .. Unit_Type (1.0)); -- OK
         --pragma Assert (cs in Unit_Type (-1.0) .. Unit_Type (1.0)); -- OK

         coscos := ct * cs; -- OK
         if abs(coscos) < Unit_Type (EPS) then
            coscos := Unit_Type (0.0);
         end if;
         -- clip inaccuracy overshoots, which helps the provers tremendously
         coscos := Clip_Unitcircle (coscos); -- cos*cos should only exceed 1.0 by imprecision: OK
      end;

      --  haversine
      declare
         cts : Unit_Type;
      begin
         --  avoid underflow
         if abs(coscos) > Unit_Type (EPS) and then abs(sdlon_half) > Unit_Type (EPS)
         then
            --pragma Assert (coscos in Unit_Type'Safe_First .. Unit_Type'Safe_Last and sdlon_half in Unit_Type'Safe_First..Unit_Type'Safe_Last); -- OK
            --  both numbers here are sufficiently different from zero
            --  both numbers are valid numerics
            --  both are large enough to avoid underflow
            cts := coscos * sdlon_half; -- Z3 can prove this steps=default, timeout=60, level=2
            cts := Clip_Unitcircle (cts);
         else
            cts := Unit_Type (0.0); -- this happens likely when target is very close (few meters)
         end if;

         --  avoid underflow
         if abs(sdlat_half) < Unit_Type (EPS) then
            sdlat_half := Unit_Type (0.0);
         end if;
         if abs(cts) < Unit_Type (EPS) then
            cts := Unit_Type (0.0);
         end if;
         haversine := sdlat_half + cts;
      end;

      if haversine = Unit_Type (0.0) then
         --  numerically too close. return null
         return 0.0*Meter;
      end if;

      declare
         function Sat_Sub_Unit is new Saturated_Subtraction (Unit_Type);
         invhav : constant Unit_Type := Sat_Sub_Unit (Unit_Type (1.0), haversine);
      begin
         return 2.0 * EARTH_RADIUS * Unit_Type (Arctan (Sqrt (haversine), Sqrt (invhav)));
      end;
   end Distance;


end Units.Navigation;