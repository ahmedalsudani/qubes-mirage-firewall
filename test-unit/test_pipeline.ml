(* Unit tests for the Pipeline module (../pipeline.ml).

   The pipeline is plain Lwt, so it can be exercised without Xen. These tests
   pin down the properties that dispatcher.ml relies on for correctness:

   - work starts in submission order (so a single flow's packet order is
     preserved on the transmit ring);
   - at most [max_in_flight] operations are ever in flight at once;
   - [submit] applies backpressure (blocks the caller) when the pipeline is
     full, rather than dropping or growing without bound;
   - an exception in one operation is isolated and still frees its slot;
   - [create] rejects a non-positive bound. *)

open Lwt.Infix

(* Yield repeatedly so any pending Lwt wakeups / condition signals settle. *)
let settle () =
  let rec loop = function
    | 0 -> Lwt.return_unit
    | n -> Lwt.pause () >>= fun () -> loop (n - 1)
  in
  loop 20

(* The forwarding handed to the pipeline runs synchronously up to its first
   await (Lwt.async runs its thunk eagerly), so recording the order in which
   each operation begins tells us the submission order is honoured. *)
let test_preserves_start_order _switch () =
  let p = Pipeline.create ~max_in_flight:100 in
  let started = ref [] in
  let items = [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9 ] in
  let rec submit_all = function
    | [] -> Lwt.return_unit
    | i :: rest ->
        Pipeline.submit p (fun () ->
            started := i :: !started;
            Lwt.pause ())
        >>= fun () -> submit_all rest
  in
  submit_all items >>= fun () ->
  settle () >>= fun () ->
  Alcotest.(check (list int))
    "operations start in submission order" items (List.rev !started);
  Lwt.return_unit

let test_backpressure _switch () =
  let max = 3 in
  let p = Pipeline.create ~max_in_flight:max in
  let running = ref 0 and peak = ref 0 in
  (* Each operation blocks on its own waiter so completion is under our control. *)
  let waiters = Array.init 8 (fun _ -> Lwt.wait ()) in
  let started = Array.make 8 false in
  let submit i =
    Pipeline.submit p (fun () ->
        started.(i) <- true;
        incr running;
        if !running > !peak then peak := !running;
        fst waiters.(i) >>= fun () ->
        decr running;
        Lwt.return_unit)
  in
  (* The first [max] submissions all start immediately and return at once. *)
  submit 0 >>= fun () ->
  submit 1 >>= fun () ->
  submit 2 >>= fun () ->
  Alcotest.(check int) "max operations running" max !running;
  (* The next submission must block: the pipeline is full. *)
  let blocked = submit 3 in
  Alcotest.(check bool)
    "submit blocks when full" true
    (match Lwt.state blocked with Lwt.Sleep -> true | _ -> false);
  Alcotest.(check bool) "blocked operation has not started" false started.(3);
  (* Free one slot; the blocked submission should now proceed. *)
  Lwt.wakeup_later (snd waiters.(0)) ();
  blocked >>= fun () ->
  settle () >>= fun () ->
  Alcotest.(check bool) "operation started once a slot freed" true started.(3);
  Alcotest.(check int) "never exceeded max_in_flight" max !peak;
  (* Drain the rest and confirm everything completes. *)
  List.iter (fun i -> Lwt.wakeup_later (snd waiters.(i)) ()) [ 1; 2; 3 ];
  settle () >>= fun () ->
  Alcotest.(check int) "all operations drained" 0 !running;
  Lwt.return_unit

let test_exception_isolated _switch () =
  let p = Pipeline.create ~max_in_flight:1 in
  (* A failing operation must not escape (which would hit Lwt's async exception
     hook and abort the unikernel) and must still release its slot. *)
  Pipeline.submit p (fun () -> failwith "boom") >>= fun () ->
  settle () >>= fun () ->
  let ran = ref false in
  Pipeline.submit p (fun () ->
      ran := true;
      Lwt.return_unit)
  >>= fun () ->
  settle () >>= fun () ->
  Alcotest.(check bool) "slot freed after exception; next operation ran" true
    !ran;
  Lwt.return_unit

let test_create_invalid _switch () =
  Alcotest.check_raises "max_in_flight < 1 is rejected"
    (Invalid_argument "Pipeline.create: max_in_flight < 1") (fun () ->
      ignore (Pipeline.create ~max_in_flight:0));
  Lwt.return_unit

let () =
  Lwt_main.run
    (Alcotest_lwt.run "pipeline"
       [
         ( "pipeline",
           [
             Alcotest_lwt.test_case "preserves start order" `Quick
               test_preserves_start_order;
             Alcotest_lwt.test_case "respects max_in_flight and backpressure"
               `Quick test_backpressure;
             Alcotest_lwt.test_case "isolates exceptions" `Quick
               test_exception_isolated;
             Alcotest_lwt.test_case "rejects invalid bound" `Quick
               test_create_invalid;
           ] );
       ])
