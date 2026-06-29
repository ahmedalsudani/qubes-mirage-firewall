(* Copyright (C) 2015, Thomas Leonard <thomas.leonard@unikernel.com>
   See the README file for details. *)

(** Bounded-concurrency pipeline for decoupling packet receive from transmit
    completion.

    On Xen, a netfront/netback transmit completes a frame only once the peer has
    been notified and has consumed it - an event-channel round-trip. If the
    receive loop waits for that completion before handling the next frame, a
    single flow is serialised at one packet per round-trip, which caps
    throughput regardless of how little CPU each packet costs.

    This module lets a bounded number of forward operations be in flight at
    once, so the round-trip latency is amortised across many packets. Once the
    bound is reached, callers block (backpressure) rather than dropping. *)

type t

(** Default number of concurrently in-flight forward operations. *)
val default_in_flight : int

(** [create ~max_in_flight] is a pipeline allowing at most [max_in_flight]
    operations in flight at once. Raises [Invalid_argument] if [max_in_flight <
    1]. *)
val create : max_in_flight:int -> t

(** [submit t fn] schedules [fn ()] to run in the background. The returned thread
    becomes determined as soon as there is room in the pipeline: immediately
    while fewer than [max_in_flight] operations are in flight, otherwise once an
    in-flight operation completes. The receive loop should bind on this thread,
    so that it keeps pulling frames while transmits are in flight but pauses when
    the pipeline is full. Exceptions raised by [fn] are caught and logged so they
    cannot escape into Lwt's async exception hook. *)
val submit : t -> (unit -> unit Lwt.t) -> unit Lwt.t
