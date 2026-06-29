(* Copyright (C) 2015, Thomas Leonard <thomas.leonard@unikernel.com>
   See the README file for details. *)

open Lwt.Infix

let src = Logs.Src.create "pipeline" ~doc:"Bounded packet-forwarding pipeline"

module Log = (val Logs.src_log src : Logs.LOG)

(* Enough to keep the transmit ring busy and hide the per-packet event-channel
   round-trip, while still bounding the memory held by in-flight frames. *)
let default_in_flight = 64

type t = {
  max_in_flight : int;
  mutable in_flight : int;
  cond : unit Lwt_condition.t;
}

let create ~max_in_flight =
  if max_in_flight < 1 then invalid_arg "Pipeline.create: max_in_flight < 1";
  { max_in_flight; in_flight = 0; cond = Lwt_condition.create () }

let rec submit t fn =
  if t.in_flight >= t.max_in_flight then
    (* Pipeline full: wait for an in-flight operation to finish before
       accepting more. This blocks the receive loop, applying backpressure
       instead of dropping frames. *)
    Lwt_condition.wait t.cond >>= fun () -> submit t fn
  else (
    t.in_flight <- t.in_flight + 1;
    Lwt.async (fun () ->
        Lwt.finalize
          (fun () ->
            Lwt.catch fn (fun ex ->
                Log.warn (fun f ->
                    f "Forwarding operation failed: %s" (Printexc.to_string ex));
                Lwt.return_unit))
          (fun () ->
            t.in_flight <- t.in_flight - 1;
            Lwt_condition.signal t.cond ();
            Lwt.return_unit));
    Lwt.return_unit)
