(* Principle
   =========

   Extension constructors (including exceptions) are generated at runtime.
   Each "exception" or extension "type t += A" statement allocate a new
   constructor.
   Type safety is guaranteed by discrimination of the constructors.

   A constructor witnesses the type of its arguments.  If two objects have the
   same constructor (by physical equality), then parameters of the constructor
   have the same type.

   But physical equality does not span accross processes, it is lost when
   marshalling.

   When unmarshalling, a new copy of the constructor is created which will
   never match existing witnesses.

   Type safety is preserved, but equalities are lost.  (Otherwise, imagine
   matching constructors generated in a similar way but with slightly different
   types and exchanged between processes: it would be possible to introduce
   arbitrary false equalities).

   The problem is the generation of unique witnesses independent of an address
   space ("pure" values).

   A solution is to delegate the generation of witnesses to an external trusted
   "gensym" service.  As long as generated symbols don't collide, type safety
   can be preserved.

   This module implements that: it turns symbols generated by an arbitrary
   service (provided as an argument to the main functor) into witnesses valid
   for OCaml runtime (locally bypassing the typechecker).

   Precautions for use
   ===================

   This implementation produce witnesses valid for OCaml 4.03 and 4.04
   runtimes.  They may or may not be valid for later versions.

   Safety relies on validity of the symbol generator.  Freshly generated symbol
   should be unique.  As usual with marshalling, this should be used between
   trusted processes.

   Symbols registered by user (via [register] function) should only be used
   with the exact same constructor -- otherwise incorrect equalities are
   generated.
*)

(** The symbol generator.
    UUID generators are valid candidates (with very low probablity of
    collisions).
*)
module type GENSYM = sig
  (* [include Hashtbl.HashedType] *)

  (** A symbol.  It should be marshallable. *)
  type t

  (** Determine if two symbols are the same.
      This should not rely on physical equality. *)
  val equal : t -> t -> bool

  (** Like [Hashtbl.HashedType.hash]. *)
  val hash : t -> int

  (** Create a new symbol.  Each call to [fresh], accross all consumers
      of the service, should return a unique symbol. *)
  val fresh : unit -> t
end

(** This module works by wrapping each extension value with a witness.

    An extension constructor can be associated to a manually chosen witness.
    Otherwise, a fresh one will be generated when wrapping for the first time.

    When unwrapping, if an extension constructor is already known for this
    witness, it will be monkey patched.
*)
module Make_unsafe (W : GENSYM) : sig

  (** A wrapped extension constructor. **)
  type +'a t

  (** Manually associate a witness to an extension constructor.

      This is useful to distribute constructors accross different processes
      (as long as each witness is used for a unique constructor).

      This function doesn't raise an exception. However:
      - if the same witness is registered twice, you risk introducing wrong
        equalities (more witnesses than constructors)
      - if the same constructor is registered twice, you risk losing equalities
        (more constructors than witnesses)

      POSSIBLE VARIANT:
      check if either witness or extension_constructor is already known
  *)
  val register : W.t -> extension_constructor -> unit

  (** Wrap a value of an extension type.
      An assertion check that the argument is not of an extension type.

      If the extension constructor has already been used (with [register]
      or through a previous use of [wrap]), the same witness will be used.

      Otherwise a new witness will be generated.

      POSSIBLE VARIANT:
      don't generate new witness (fail, or ...)
  *)
  val wrap : 'a -> 'a t

  (** Unwrap a value of an extension type, so that it can be matched again.

      If the value comes from the same address space (not unmarshalled),
      it is returned unchanged.
      If the witness is not known, the value is returned unchanged.
      Otherwise, it is patched to match local process.

      POSSIBLE VARIANT:
      don't unwrap if witness is unknown
  *)
  val unwrap : 'a t -> 'a

  (** Get the witness of a wrapped value *)
  val witness : 'a t -> W.t
end