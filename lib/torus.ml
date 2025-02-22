open Linalg

let epsilon = 0.001

module Quartic = struct
  type t = { a : float; b : float; c : float; d : float; e : float }

  let normalise q =
    { a = 1.0; b = q.b /. q.a; c = q.c /. q.a; d = q.d /. q.a; e = q.e /. q.a }

  let compute q x =
    let open Complex in
    let x2 = mul x x in
    let x3 = mul x2 x in
    let x4 = mul x2 x2 in
    let bx3 = mul { re = q.b; im = 0.0 } x3 in
    let cx2 = mul { re = q.c; im = 0.0 } x2 in
    let dx = mul { re = q.d; im = 0.0 } x in
    let e = { re = q.e; im = 0.0 } in
    List.fold_left add x4 [ bx3; cx2; dx; e ]
end

module DurandKerner = struct
  type t = { p : Complex.t; q : Complex.t; r : Complex.t; s : Complex.t }

  let complex_diff_epsilon c1 c2 epsilon =
    Complex.norm2 (Complex.sub c1 c2) < epsilon

  let roots_diff_epsilon rts1 rts2 epsilon =
    complex_diff_epsilon rts1.p rts2.p epsilon
    && complex_diff_epsilon rts1.q rts2.q epsilon
    && complex_diff_epsilon rts1.r rts2.r epsilon
    && complex_diff_epsilon rts1.s rts2.s epsilon

  let iterate (poly : Quartic.t) (rts : t) =
    let open Complex in
    let p =
      sub rts.p
        (div
           (Quartic.compute poly rts.p)
           (List.fold_left mul (sub rts.p rts.q)
              [ sub rts.p rts.r; sub rts.p rts.s ]))
    in
    let q =
      sub rts.q
        (div
           (Quartic.compute poly rts.q)
           (List.fold_left mul (sub rts.q p)
              [ sub rts.q rts.r; sub rts.q rts.s ]))
    in
    let r =
      sub rts.r
        (div
           (Quartic.compute poly rts.r)
           (List.fold_left mul (sub rts.r p) [ sub rts.r q; sub rts.r rts.s ]))
    in
    let s =
      sub rts.s
        (div
           (Quartic.compute poly rts.s)
           (List.fold_left mul (sub rts.s p) [ sub rts.s q; sub rts.s r ]))
    in
    { p; q; r; s }

  let rec find_roots_aux (poly : Quartic.t) (rts : t) =
    let rts' = iterate poly rts in
    if roots_diff_epsilon rts rts' epsilon then rts'
    else find_roots_aux poly rts'

  let find_roots poly =
    let poly' = Quartic.normalise poly in
    let open Complex in
    let p = { re = 1.0; im = 0.0 } in
    let q = { re = 0.4; im = 0.9 } in
    let r = mul q q in
    let s = mul r q in
    find_roots_aux poly' { p; q; r; s }

  let get_real_roots poly =
    let rts = find_roots poly in
    let l = [ rts.p; rts.q; rts.r; rts.s ] in
    let l' = List.filter (fun (c : Complex.t) -> abs_float c.im < epsilon) l in
    List.map (fun (c : Complex.t) -> c.re) l'
end

module Sphere = struct
  type t = { r : float }

  (* http://kylehalladay.com/blog/tutorial/math/2013/12/24/Ray-Sphere-Intersection.html
     Warning: Code sample in source has errors *)
  let intersection s (r : Ray.t) =
    let open Vec in
    (* let l = s.o - r.o in *)
    let l = make_vec (-.r.o.x) (-.r.o.y) (-.r.o.z) in
    let tc = dot l r.d in
    if tc < 0.0 then false
    else
      let d2 = magnitude2 l -. (tc *. tc) in
      let r2 = s.r *. s.r in
      if d2 > r2 then false else true
end

type t = {
  maj_r : float;
  min_r : float;
  trf : Transform.t;
  t : Mat.t;
  inv_t : Mat.t;
  bound_s : Sphere.t;
  color : Vec.t;
}

let create ~maj_r ~min_r (trf : Transform.t) (color : Vec.t) =
  let bound_s : Sphere.t = { r = maj_r +. min_r } in
  {
    maj_r;
    min_r;
    trf;
    t = Transform.generate trf;
    inv_t = Transform.generate_inverse trf;
    bound_s;
    color;
  }

(* http://blog.marcinchwedczuk.pl/ray-tracing-torus *)
let generate_quartic (r : Ray.t) t : Quartic.t =
  let a_sqrt = (r.d.x *. r.d.x) +. (r.d.y *. r.d.y) +. (r.d.z *. r.d.z) in
  let od = (r.o.x *. r.d.x) +. (r.o.y *. r.d.y) +. (r.o.z *. r.d.z) in
  let orr =
    (r.o.x *. r.o.x) +. (r.o.y *. r.o.y) +. (r.o.z *. r.o.z)
    -. ((t.min_r *. t.min_r) +. (t.maj_r *. t.maj_r))
  in
  let a = a_sqrt *. a_sqrt in
  let b = 4. *. a_sqrt *. od in
  let c =
    (2. *. a_sqrt *. orr)
    +. (4. *. od *. od)
    +. (4. *. t.maj_r *. t.maj_r *. r.d.y *. r.d.y)
  in
  let d = (4. *. orr *. od) +. (8. *. t.maj_r *. t.maj_r *. r.o.y *. r.d.y) in
  let e =
    (orr *. orr)
    -. (4. *. t.maj_r *. t.maj_r *. ((t.min_r *. t.min_r) -. (r.o.y *. r.o.y)))
  in
  { a; b; c; d; e }

let intersection t r =
  let r' = Mat.transform_ray t.inv_t r in
  if not (Sphere.intersection t.bound_s r') then None
  else
    let q = generate_quartic r' t in
    let roots = DurandKerner.get_real_roots q in
    let dist =
      List.filter (fun x -> x > epsilon) roots |> List.fold_left min infinity
    in
    if Float.is_infinite dist then None else Some (Ray.point_along r dist, dist)

let normal t (p : Vec.t) =
  let p' = Mat.( * ) t.inv_t p in
  let open Vec in
  let v_on_circle = t.maj_r * normalised (make_vec p'.x 0.0 p'.z) in
  let p_on_circle = make_point v_on_circle.x 0.0 v_on_circle.z in
  normalised (p - Mat.( * ) t.t p_on_circle)

let maj_r t = t.maj_r
let min_r t = t.min_r
let transform t = t.trf
let mat t = t.t
let color t : Vec.t = t.color
