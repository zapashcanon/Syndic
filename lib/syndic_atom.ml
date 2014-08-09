open Syndic_common.XML
open Syndic_common.Util
module XML = Syndic_xml

module Date = struct
  open CalendarLib
  open Printf
  open Scanf

  (* RFC3339 date *)
  let of_string s =
    let make_date year month day h m s z =
      let date = Calendar.Date.make year month day in
      let t = Calendar.Time.(make h m (Second.from_float s)) in
      if z = "" || z.[0] = 'Z' then
        Calendar.(create date t)
      else
        let tz =
          let open Calendar.Time in
          sscanf z "%i:%i" (fun h m -> Period.make h m (Second.from_int 0)) in
        Calendar.(create date (Time.add t tz))
    in
    (* Sometimes, the seconds have a decimal point
       See https://forge.ocamlcore.org/tracker/index.php?func=detail&aid=1414&group_id=83&atid=418 *)
    try sscanf s "%i-%i-%iT%i:%i:%f%s" make_date
    with Scanf.Scan_failure _ ->
      invalid_arg(sprintf "Syndic.Atom.Date.of_string: cannot parse %S" s)
end

let atom_ns = "http://www.w3.org/2005/Atom"
let xhtml_ns = "http://www.w3.org/1999/xhtml"
let namespaces = [ atom_ns ]

type rel =
  | Alternate
  | Related
  | Self
  | Enclosure
  | Via
  | Link of Uri.t

type link =
  {
    href: Uri.t;
    rel: rel;
    type_media: string option;
    hreflang: string option;
    title: string option;
    length: int option;
  }

type link' = [
  | `HREF of string
  | `Rel of string
  | `Type of string
  | `HREFLang of string
  | `Title of string
  | `Length of string
]

module Error = struct
  include Syndic_error

  exception Duplicate_Link of (Uri.t * string * string) * (string * string)

  let raise_duplicate_link { href; type_media; hreflang; _}
                           (type_media', hreflang') =
    let ty = (function Some a -> a | None -> "(none)") type_media in
    let hl = (function Some a -> a | None -> "(none)") hreflang in
    let ty' = (function "" -> "(none)" | s -> s) type_media' in
    let hl' = (function "" -> "(none)" | s -> s) hreflang' in
    raise (Duplicate_Link ((href, ty, hl), (ty', hl')))

  let string_of_duplicate_exception ((uri, ty, hl), (ty', hl')) =
    let buffer = Buffer.create 16 in
    Buffer.add_string buffer "Duplicate link between [href: ";
    Buffer.add_string buffer (Uri.to_string uri);
    Buffer.add_string buffer ", ty: ";
    Buffer.add_string buffer ty;
    Buffer.add_string buffer ", hl: ";
    Buffer.add_string buffer hl;
    Buffer.add_string buffer "] and [ty: ";
    Buffer.add_string buffer ty';
    Buffer.add_string buffer ", hl: ";
    Buffer.add_string buffer hl';
    Buffer.add_string buffer "]";
    Buffer.contents buffer
end


(* The actual XML content is supposed to be inside a <div> which is NOT
   part of the content. *)
let rec get_xml_content xml0 = function
  | XML.Data s :: tl -> if only_whitespace s then get_xml_content xml0 tl
                       else xml0 (* unexpected *)
  | XML.Node(tag, data) :: tl when tag_is tag "div" ->
     let is_space =
       List.for_all (function XML.Data s -> only_whitespace s | _ -> false) tl in
     if is_space then data else xml0
  | _ -> xml0

let no_namespace = Some ""
let rm_namespace _ = no_namespace

(* For HTML, the spec says the whole content needs to be escaped
   http://tools.ietf.org/html/rfc4287#section-3.1.1.2 (some feeds use
   <![CDATA[ ]]>) so a single data item should be present.
   If not, assume the HTML was properly parsed and convert it back
   to a string as it should. *)
let get_html_content html =
  match html with
  | [XML.Data d] -> d
  | h ->
     (* It is likely that, when the HTML was parsed, the Atom
        namespace was applied.  Remove it. *)
     String.concat "" (List.map (XML.to_string ~ns_prefix:rm_namespace) h)

type text_construct =
  | Text of string
  | Html of string
  | Xhtml of Syndic_xml.t list

let text_construct_of_xml (((tag, attr), data): Xmlm.tag * t list) =
  match find (fun a -> attr_is a "type") attr with
  | Some(_, "html") -> Html(get_html_content data)
  | Some(_, "application/xhtml+xml")
  | Some(_, "xhtml") -> Xhtml(get_xml_content data data)
  | _ -> Text(get_leaf data)


type author =
  {
    name: string;
    uri: Uri.t option;
    email: string option;
  }

type author' = [
  | `Name of string
  | `URI of Uri.t
  | `Email of string
]

let make_author datas (l : [< author'] list) =
  (* element atom:name { text } *)
  let name = match find (function `Name _ -> true | _ -> false) l with
    | Some (`Name s) -> s
    | _ ->
       (* The spec mandates that <author><name>name</name></author>
          but severay feed just do <author>name</author> *)
       get_leaf datas in
  (* element atom:uri { atomUri }? *)
  let uri = match find (function `URI _ -> true | _ -> false) l with
    | Some (`URI u) -> Some u
    | _ -> None
  in
  (* element atom:email { atomEmailAddress }? *)
  let email = match find (function `Email _ -> true | _ -> false) l with
    | Some (`Email e) -> Some e
    | _ -> None
  in
  ({ name; uri; email; } : author)

let author_name_of_xml (tag, datas) =
  try get_leaf datas
  with Error.Expected_Data -> "" (* mandatory ? *)

let author_uri_of_xml (tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Error.Expected_Data ->
    Error.raise_expectation Error.Data (Error.Tag "author/uri")

let author_email_of_xml (tag, datas) =
  try get_leaf datas
  with Error.Expected_Data -> "" (* mandatory ? *)

(* {[  atomAuthor = element atom:author { atomPersonConstruct } ]}
   where

    atomPersonConstruct =
        atomCommonAttributes,
        (element atom:name { text }
         & element atom:uri { atomUri }?
         & element atom:email { atomEmailAddress }?
         & extensionElement * )

   This specification assigns no significance to the order of
   appearance of the child elements in a Person construct.  *)
let author_of_xml =
  let data_producer = [
    ("name", (fun ctx a -> `Name (author_name_of_xml a)));
    ("uri", (fun ctx a -> `URI (author_uri_of_xml a)));
    ("email", (fun ctx a -> `Email (author_email_of_xml a)));
  ] in
  fun ((_, datas) as xml) ->
  generate_catcher ~namespaces ~data_producer (make_author datas) xml

let author_of_xml' =
  let data_producer = [
    ("name", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Name a)));
    ("uri", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `URI a)));
    ("email", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Email a)));
  ] in
  generate_catcher ~namespaces ~data_producer (fun x -> x)

type category =
  {
    term: string;
    scheme: Uri.t option;
    label: string option;
  }

type category' = [
  | `Term of string
  | `Scheme of string
  | `Label of string
]

let make_category (l : [< category'] list) =
  (* attribute term { text } *)
  let term = match find (function `Term _ -> true | _ -> false) l with
    | Some (`Term t) -> t
    | _ -> Error.raise_expectation (Error.Attr "term") (Error.Tag "category")
  in
  (* attribute scheme { atomUri }? *)
  let scheme =
    match find (function `Scheme _ -> true | _ -> false) l with
    | Some (`Scheme u) -> Some (Uri.of_string u)
    | _ -> None
  in
  (* attribute label { text }? *)
  let label = match find (function `Label _ -> true | _ -> false) l with
    | Some (`Label l) -> Some l
    | _ -> None
  in
  ({ term; scheme; label; } : category)


(* atomCategory =
     element atom:category {
        atomCommonAttributes,
        attribute term { text },
        attribute scheme { atomUri }?,
        attribute label { text }?,
        undefinedContent
     }
 *)
let category_of_xml, category_of_xml' =
  let attr_producer = [
    ("term", (fun ctx a -> `Term a));
    ("scheme", (fun ctx a -> `Scheme a));
    ("label", (fun ctx a -> `Label a))
  ] in
  generate_catcher ~attr_producer make_category,
  generate_catcher ~attr_producer (fun x -> x)

let make_contributor = make_author
let contributor_of_xml = author_of_xml
let contributor_of_xml' = author_of_xml'

type generator =
  {
    version: string option;
    uri: Uri.t option;
    content: string;
  }

type generator' = [
  | `URI of string
  | `Version of string
  | `Content of string
]

let make_generator (l : [< generator'] list) =
  (* text *)
  let content = match find (function `Content _ -> true | _ -> false) l with
    | Some ((`Content c)) -> c
    | _ -> Error.raise_expectation Error.Data (Error.Tag "generator")
  in
  (* attribute version { text }? *)
  let version = match find (function `Version _ -> true | _ -> false) l with
    | Some ((`Version v)) -> Some v
    | _ -> None
  in
  (* attribute uri { atomUri }? *)
  let uri = match find (function `URI _ -> true | _ -> false) l with
    | Some ((`URI u)) -> Some (Uri.of_string u)
    | _ -> None
  in ({ version; uri; content; } : generator)

(* atomGenerator = element atom:generator {
      atomCommonAttributes,
      attribute uri { atomUri }?,
      attribute version { text }?,
      text
    }
 *)
let generator_of_xml, generator_of_xml' =
  let attr_producer = [
    ("version", (fun ctx a -> `Version a));
    ("uri", (fun ctx a -> `URI a));
  ] in
  let leaf_producer ctx data = `Content data in
  generate_catcher ~attr_producer ~leaf_producer make_generator,
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

type icon = Uri.t
type icon' = [ `URI of string ]

let make_icon (l : [< icon'] list) =
  (** (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> (Uri.of_string u)
    | _ -> Error.raise_expectation Error.Data (Error.Tag "icon")
  in uri

(* atomIcon = element atom:icon {
      atomCommonAttributes,
    }
 *)
let icon_of_xml, icon_of_xml' =
  let leaf_producer ctx data = `URI data in
  generate_catcher ~leaf_producer make_icon,
  generate_catcher ~leaf_producer (fun x -> x)

type id = Uri.t
type id' = [ `URI of string ]

let make_id (l : [< id'] list) =
  (* (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> (Uri.of_string u)
    | _ -> Error.raise_expectation Error.Data (Error.Tag "id")
  in uri

(* atomId = element atom:id {
      atomCommonAttributes,
      (atomUri)
    }
 *)
let id_of_xml, id_of_xml' =
  let leaf_producer ctx data = `URI data in
  generate_catcher ~leaf_producer make_id,
  generate_catcher ~leaf_producer (fun x -> x)

let rel_of_string s = match String.lowercase (String.trim s) with
  | "alternate" -> Alternate
  | "related" -> Related
  | "self" -> Self
  | "enclosure" -> Enclosure
  | "via" -> Via
  | uri -> Link (Uri.of_string uri) (* RFC 4287 § 4.2.7.2 *)

let make_link (l : [< link'] list) =
  (* attribute href { atomUri } *)
  let href = match find (function `HREF _ -> true | _ -> false) l with
    | Some (`HREF u) -> (Uri.of_string u)
    | _ -> Error.raise_expectation (Error.Attr "href") (Error.Tag "link")
  in
  (* attribute rel { atomNCName | atomUri }? *)
  let rel = match find (function `Rel _ -> true | _ -> false) l with
    | Some (`Rel r) -> rel_of_string r
    | _ -> Alternate (* cf. RFC 4287 § 4.2.7.2 *)
  in
  (* attribute type { atomMediaType }? *)
  let type_media = match find (function `Type _ -> true | _ -> false) l with
    | Some (`Type t) -> Some t
    | _ -> None
  in
  (* attribute hreflang { atomLanguageTag }? *)
  let hreflang =
    match find (function `HREFLang _ -> true | _ -> false) l with
    | Some (`HREFLang l) -> Some l
    | _ -> None
  in
  (* attribute title { text }? *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title s) -> Some s
    | _ -> None
  in
  (* attribute length { text }? *)
  let length = match find (function `Length _ -> true | _ -> false) l with
    | Some (`Length i) -> Some (int_of_string i)
    | _ -> None
  in
  ({ href; rel; type_media; hreflang; title; length; } : link)

(* atomLink =
    element atom:link {
        atomCommonAttributes,
        attribute href { atomUri },
        attribute rel { atomNCName | atomUri }?,
        attribute type { atomMediaType }?,
        attribute hreflang { atomLanguageTag }?,
        attribute title { text }?,
        attribute length { text }?,
        undefinedContent
  }
 *)
let link_of_xml, link_of_xml' =
  let attr_producer = [
    ("href", (fun ctx a -> `HREF a));
    ("rel", (fun ctx a -> `Rel a));
    ("type", (fun ctx a -> `Type a));
    ("hreflang", (fun ctx a -> `HREFLang a));
    ("title", (fun ctx a -> `Title a));
    ("length", (fun ctx a -> `Length a));
  ] in
  generate_catcher ~attr_producer make_link,
  generate_catcher ~attr_producer (fun x -> x)

type logo = Uri.t
type logo' = [ `URI of string ]

let make_logo (l : [< logo'] list) =
  (* (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> (Uri.of_string u)
    | _ -> Error.raise_expectation Error.Data (Error.Tag "logo")
  in uri

(* atomLogo = element atom:logo {
      atomCommonAttributes,
      (atomUri)
    }
 *)
let logo_of_xml, logo_of_xml' =
  let leaf_producer ctx data = `URI data in
  generate_catcher ~leaf_producer make_logo,
  generate_catcher ~leaf_producer (fun x -> x)

type published = CalendarLib.Calendar.t
type published' = [ `Date of string ]

let make_published (l : [< published'] list) =
  (* atom:published { atomDateConstruct } *)
  let date = match find (fun (`Date _) -> true) l with
    | Some (`Date d) -> Date.of_string d
    | _ -> Error.raise_expectation Error.Data (Error.Tag "published")
  in date

(* atomPublished = element atom:published { atomDateConstruct } *)
let published_of_xml, published_of_xml' =
  let leaf_producer ctx data = `Date data in
  generate_catcher ~leaf_producer make_published,
  generate_catcher ~leaf_producer (fun x -> x)


type rights = text_construct
type rights' = [ `Data of Syndic_xml.t list ]

let rights_of_xml = text_construct_of_xml

(* atomRights = element atom:rights { atomTextConstruct } *)
let rights_of_xml' (((tag, attr), data): Xmlm.tag * t list) =
  `Data data

type title = text_construct
type title' = [ `Data of Syndic_xml.t list ]

let title_of_xml = text_construct_of_xml

(* atomTitle = element atom:title { atomTextConstruct } *)
let title_of_xml' (((tag, attr), data): Xmlm.tag * t list) =
  `Data data

type subtitle = text_construct
type subtitle' = [ `Data of Syndic_xml.t list ]

let subtitle_of_xml = text_construct_of_xml

(* atomSubtitle = element atom:subtitle { atomTextConstruct } *)
let subtitle_of_xml' (((tag, attr), data): Xmlm.tag * t list) =
  `Data data

type updated = CalendarLib.Calendar.t
type updated' = [ `Date of string ]

let make_updated (l : [< updated'] list) =
  (* atom:updated { atomDateConstruct } *)
  let updated = match find (fun (`Date _) -> true) l with
    | Some (`Date d) -> Date.of_string d
    | _ -> Error.raise_expectation Error.Data (Error.Tag "updated")
  in updated

(* atomUpdated = element atom:updated { atomDateConstruct } *)
let updated_of_xml, updated_of_xml' =
  let leaf_producer ctx data = `Date data in
  generate_catcher ~leaf_producer make_updated,
  generate_catcher ~leaf_producer (fun x -> x)

type source =
  {
    authors: author * author list;
    categories: category list;
    contributors: author list;
    generator: generator option;
    icon: icon option;
    id: id;
    links: link * link list;
    logo: logo option;
    rights: rights option;
    subtitle: subtitle option;
    title: title;
    updated: updated option;
  }

type source' = [
  | `Author of author
  | `Category of category
  | `Contributor of author
  | `Generator of generator
  | `Icon of icon
  | `ID of id
  | `Link of link
  | `Logo of logo
  | `Subtitle of subtitle
  | `Title of title
  | `Rights of rights
  | `Updated of updated
]

let make_source ~entry_authors (l : [< source'] list) =
  (* atomAuthor* *)
  let authors =
    List.fold_left (fun acc -> function `Author x -> x :: acc | _ -> acc) [] l in
  let authors = match authors, entry_authors with
    | x :: r, _ -> x, r
    | [], x :: r -> x, r
    | [], [] -> Error.raise_expectation (Error.Tag "author") (Error.Tag "source")
  in
  (* atomCategory* *)
  let categories =
    List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc)
      [] l in
  (* atomContributor* *)
  let contributors =
    List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc)
      [] l in
  (* atomGenerator? *)
  let generator =
    match find (function `Generator _ -> true | _ -> false) l with
    | Some (`Generator g) -> Some g
    | _ -> None
  in
  (* atomIcon? *)
  let icon = match find (function `Icon _ -> true | _ -> false) l with
    | Some (`Icon u) -> Some u
    | _ -> None
  in
  (* atomId? *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Error.raise_expectation (Error.Tag "id") (Error.Tag "source")
  in
  (* atomLink* *)
  let links =
    (function
      | [] -> Error.raise_expectation (Error.Tag "link") (Error.Tag "source")
      | x :: r -> (x, r))
      (List.fold_left (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l)
  in
  (* atomLogo? *)
  let logo = match find (function `Logo _ -> true | _ -> false) l with
    | Some (`Logo u) -> Some u
    | _ -> None
  in
  (* atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None
  in
  (* atomSubtitle? *)
  let subtitle = match find (function `Subtitle _ -> true | _ -> false) l with
    | Some (`Subtitle s) -> Some s
    | _ -> None
  in
  (* atomTitle? *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title s) -> s
    | _ -> Error.raise_expectation (Error.Tag "title") (Error.Tag "source")
  in
  (* atomUpdated? *)
  let updated = match find (function `Updated _ -> true | _ -> false) l with
    | Some (`Updated d) -> Some d
    | _ -> None
  in
  ({ authors;
     categories;
     contributors;
     generator;
     icon;
     id;
     links;
     logo;
     rights;
     subtitle;
     title;
     updated; } : source)

(* atomSource =
    element atom:source {
        atomCommonAttributes,
        (atomAuthor*
         & atomCategory*
         & atomContributor*
         & atomGenerator?
         & atomIcon?
         & atomId?
         & atomLink*
         & atomLogo?
         & atomRights?
         & atomSubtitle?
         & atomTitle?
         & atomUpdated?
         & extensionElement * )
      }
 *)
let source_of_xml =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml a)));
    ("category", (fun ctx a -> `Category (category_of_xml a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml a)));
    ("generator", (fun ctx a -> `Generator (generator_of_xml a)));
    ("icon", (fun ctx a -> `Icon (icon_of_xml a)));
    ("id", (fun ctx a -> `ID (id_of_xml a)));
    ("link", (fun ctx a -> `Link (link_of_xml a)));
    ("logo", (fun ctx a -> `Logo (logo_of_xml a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml a)));
    ("subtitle", (fun ctx a -> `Subtitle (subtitle_of_xml a)));
    ("title", (fun ctx a -> `Title (title_of_xml a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml a)));
  ] in
  fun ~entry_authors ->
  generate_catcher ~namespaces ~data_producer (make_source ~entry_authors)

let source_of_xml' =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml' a)));
    ("category", (fun ctx a -> `Category (category_of_xml' a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml' a)));
    ("generator", (fun ctx a -> `Generator (generator_of_xml' a)));
    ("icon", (fun ctx a -> `Icon (icon_of_xml' a)));
    ("id", (fun ctx a -> `ID (id_of_xml' a)));
    ("link", (fun ctx a -> `Link (link_of_xml' a)));
    ("logo", (fun ctx a -> `Logo (logo_of_xml' a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml' a)));
    ("subtitle", (fun ctx a -> `Subtitle (subtitle_of_xml' a)));
    ("title", (fun ctx a -> `Title (title_of_xml' a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml' a)));
  ] in
  generate_catcher ~namespaces ~data_producer (fun x -> x)


type mime = string

type content =
  | Text of string
  | Html of string
  | Xhtml of Syndic_xml.t list
  | Mime of mime * string
  | Src of mime option * Uri.t

type content' = [
  | `Type of string
  | `SRC of string
  | `Data of Syndic_xml.t list
]


(*  atomInlineTextContent =
      element atom:content {
          atomCommonAttributes,
          attribute type { "text" | "html" }?,
          (text)*
    }

    atomInlineXHTMLContent =
      element atom:content {
          atomCommonAttributes,
          attribute type { "xhtml" },
          xhtmlDiv
    }

    atomInlineOtherContent =
      element atom:content {
          atomCommonAttributes,
          attribute type { atomMediaType }?,
          (text|anyElement)*
    }

    atomOutOfLineContent =
      element atom:content {
          atomCommonAttributes,
          attribute type { atomMediaType }?,
          attribute src { atomUri },
          empty
    }

    atomContent = atomInlineTextContent
    | atomInlineXHTMLContent
    | atomInlineOtherContent
    | atomOutOfLineContent
 *)
let content_of_xml (((tag, attr), data): Xmlm.tag * t list) : content =
  (* MIME ::= attribute type { "text" | "html" }?
              | attribute type { "xhtml" }
              | attribute type { atomMediaType }? *)
  (* attribute src { atomUri } | none
     If src s present, [data] MUST be empty. *)
  match find (fun a -> attr_is a "src") attr with
  | Some (_, src) ->
     let mime = match find (fun a -> attr_is a "type") attr with
       | Some(_, ty) -> Some ty
       | None -> None in
     Src(mime, Uri.of_string src)
  | None ->
     (* (text)*
      *  | xhtmlDiv
      *  | (text|anyElement)*
      *  | none *)
     match find (fun a -> attr_is a "type") attr with
     | Some (_, "text") | None -> Text(get_leaf data)
     | Some (_, "html") -> Html(get_html_content data)
     | Some (_, "xhtml") -> Xhtml(get_xml_content data data)
     | Some (_, mime) -> Mime(mime, get_leaf data)

let content_of_xml' (((tag, attr), data): Xmlm.tag * t list) =
  let l = match find (fun a -> attr_is a "src") attr with
    | Some(_, src) -> [`SRC src]
    | None -> [] in
  let l = match find (fun a -> attr_is a "type") attr with
    | Some(_, ty) -> `Type ty :: l
    | None -> l in
  `Data data :: l


type summary = text_construct
type summary' = [ `Data of Syndic_xml.t list ]

(* atomSummary = element atom:summary { atomTextConstruct } *)
let summary_of_xml = text_construct_of_xml

let summary_of_xml' (((tag, attr), data): Xmlm.tag * t list) =
  `Data data

type entry =
  {
    authors: author * author list;
    categories: category list;
    content: content option;
    contributors: author list;
    id: id;
    links: link list;
    published: published option;
    rights: rights option;
    sources: source list;
    summary: summary option;
    title: title;
    updated: updated;
  }

type entry' = [
  | `Author of author
  | `Category of category
  | `Contributor of author
  | `ID of id
  | `Link of link
  | `Published of published
  | `Rights of rights
  | `Source of source
  | `Content of content
  | `Summary of summary
  | `Title of title
  | `Updated of updated
]

module LinkOrder
  : Set.OrderedType with type t = string * string =
struct
  type t = string * string
  let compare (a : t) (b : t) = match compare (fst a) (fst b) with
    | 0 -> compare (snd a) (snd b)
    | n -> n
end

module LinkSet = Set.Make(LinkOrder)

let uniq_link_alternate (l : link list) =
  let rec aux acc = function
    | [] -> l

    | ({ rel; type_media = Some ty; hreflang = Some hl; _ } as x) :: r
      when rel = Alternate ->
      if LinkSet.mem (ty, hl) acc
      then Error.raise_duplicate_link x (LinkSet.find (ty, hl) acc)
      else aux (LinkSet.add (ty, hl) acc) r

    | ({ rel; type_media = None; hreflang = Some hl; _ } as x) :: r
      when rel = Alternate ->
      if LinkSet.mem ("", hl) acc
      then Error.raise_duplicate_link x (LinkSet.find ("", hl) acc)
      else aux (LinkSet.add ("", hl) acc) r

    | ({ rel; type_media = Some ty; hreflang = None; _ } as x) :: r
      when rel = Alternate ->
      if LinkSet.mem (ty, "") acc
      then Error.raise_duplicate_link x (LinkSet.find (ty, "") acc)
      else aux (LinkSet.add (ty, "") acc) r

    | ({ rel; type_media = None; hreflang = None; _ } as x) :: r
      when rel = Alternate ->
      if LinkSet.mem ("", "") acc
      then Error.raise_duplicate_link x (LinkSet.find ("", "") acc)
      else aux (LinkSet.add ("", "") acc) r

    | x :: r -> aux acc r
  in aux LinkSet.empty l

type feed' = [
  | `Author of author
  | `Category of category
  | `Contributor of author
  | `Generator of generator
  | `Icon of icon
  | `ID of id
  | `Link of link
  | `Logo of logo
  | `Rights of rights
  | `Subtitle of subtitle
  | `Title of title
  | `Updated of updated
  | `Entry of entry
]


let make_entry ~(feed_authors: author list) l =
  let authors =
    List.fold_left (fun acc -> function `Author x -> x :: acc | _ -> acc) [] l in
  let authors = match authors with
    (* default author is feed/author, see RFC 4287 § 4.1.2 *)
    | [] -> feed_authors
    | _ -> authors in
  (* atomSource? (pass the authors known so far) *)
  let sources = List.fold_left
                  (fun acc -> function `Source x -> x :: acc | _ -> acc) [] l in
  let sources = List.map (source_of_xml ~entry_authors:authors) sources in
  let authors = match authors, sources with
    | a0 :: a, _ -> a0, a
    | [], s :: src ->
       (* Collect authors given in [sources] *)
       let a0, a1 = s.authors in
       let a2 =
         List.map (fun (s: source) -> let a1, a = s.authors in a1 :: a) src in
       a0, List.concat (a1 :: a2)
    | [], [] ->
       Error.raise_expectation (Error.Tag "author") (Error.Tag "entry")
  (* atomCategory* *)
  in let categories = List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc) [] l
      (* atomContributor* *)
  in let contributors = List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc) [] l in
  (* atomId *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Error.raise_expectation (Error.Tag "id") (Error.Tag "entry")
    (* atomLink* *)
  in let links = List.fold_left
      (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l in
  (* atomPublished? *)
  let published = match find (function `Published _ -> true | _ -> false) l with
    | Some (`Published s) -> Some s
    | _ -> None
  in
  (* atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None in
  (* atomContent? *)
  let content = match find (function `Content _ -> true | _ -> false) l with
    | Some (`Content c) -> Some c
    | _ -> None
  in
  (* atomSummary? *)
  let summary = match find (function `Summary _ -> true | _ -> false) l with
    | Some (`Summary s) -> Some s
    | _ -> None
  in
  (* atomTitle *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ -> Error.raise_expectation (Error.Tag "title") (Error.Tag "entry")
  in
  (* atomUpdated *)
  let updated = match find (function `Updated _ -> true | _ -> false) l with
    | Some (`Updated u) -> u
    | _ -> Error.raise_expectation (Error.Tag "updated") (Error.Tag "entry")
  in
  ({ authors;
     categories;
     content;
     contributors;
     id;
     links = uniq_link_alternate links;
     published;
     rights;
     sources;
     summary;
     title;
     updated; } : entry)

(* atomEntry =
     element atom:entry {
        atomCommonAttributes,
        (atomAuthor*
         & atomCategory*
         & atomContent?
         & atomContributor*
         & atomId
         & atomLink*
         & atomPublished?
         & atomRights?
         & atomSource?
         & atomSummary?
         & atomTitle
         & atomUpdated
         & extensionElement * )
      }
 *)
let entry_of_xml =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml a)));
    ("category", (fun ctx a -> `Category (category_of_xml a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml a)));
    ("id", (fun ctx a -> `ID (id_of_xml a)));
    ("link", (fun ctx a -> `Link (link_of_xml a)));
    ("published", (fun ctx a -> `Published (published_of_xml a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml a)));
    ("source", (fun ctx a -> `Source a));
    ("content", (fun ctx a -> `Content (content_of_xml a)));
    ("summary", (fun ctx a -> `Summary (summary_of_xml a)));
    ("title", (fun ctx a -> `Title (title_of_xml a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml a)));
  ] in
  fun ~feed_authors ->
  generate_catcher ~namespaces ~data_producer (make_entry ~feed_authors)

let entry_of_xml' =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml' a)));
    ("category", (fun ctx a -> `Category (category_of_xml' a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml' a)));
    ("id", (fun ctx a -> `ID (id_of_xml' a)));
    ("link", (fun ctx a -> `Link (link_of_xml' a)));
    ("published", (fun ctx a -> `Published (published_of_xml' a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml' a)));
    ("source", (fun ctx a -> `Source (source_of_xml' a)));
    ("content", (fun ctx a -> `Content (content_of_xml' a)));
    ("summary", (fun ctx a -> `Summary (summary_of_xml' a)));
    ("title", (fun ctx a -> `Title (title_of_xml' a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml' a)));
  ] in
  generate_catcher ~namespaces ~data_producer (fun x -> x)

type feed =
  {
    authors: author list;
    categories: category list;
    contributors: author list;
    generator: generator option;
    icon: icon option;
    id: id;
    links: link list;
    logo: logo option;
    rights: rights option;
    subtitle: subtitle option;
    title: title;
    updated: updated;
    entries: entry list;
  }

let make_feed (l : _ list) =
  (* atomAuthor* *)
  let authors = List.fold_left
      (fun acc -> function `Author x -> x :: acc | _ -> acc) [] l in
  (* atomCategory* *)
  let categories = List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc) [] l in
  (* atomContributor* *)
  let contributors = List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc) [] l in
  (* atomLink* *)
  let links = List.fold_left
      (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l in
  (* atomGenerator? *)
  let generator = match find (function `Generator _ -> true | _ -> false) l with
    | Some (`Generator g) -> Some g
    | _ -> None
  in
  (* atomIcon? *)
  let icon = match find (function `Icon _ -> true | _ -> false) l with
    | Some (`Icon i) -> Some i
    | _ -> None
  in
  (* atomId *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Error.raise_expectation (Error.Tag "id") (Error.Tag "feed")
  in
  (* atomLogo? *)
  let logo = match find (function `Logo _ -> true | _ -> false) l with
    | Some (`Logo l) -> Some l
    | _ -> None
  in
  (* atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None
  in
  (* atomSubtitle? *)
  let subtitle = match find (function `Subtitle _ -> true | _ -> false) l with
    | Some (`Subtitle s) -> Some s
    | _ -> None
  in
  (* atomTitle *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ -> Error.raise_expectation (Error.Tag "title") (Error.Tag "feed")
  in
  (* atomUpdated *)
  let updated = match find (function `Updated _ -> true | _ -> false) l with
    | Some (`Updated u) -> u
    | _ -> Error.raise_expectation (Error.Tag "updated") (Error.Tag "feed")
  in
  (* atomEntry* *)
  let entries =
    List.fold_left
      (fun acc -> function `Entry x -> entry_of_xml ~feed_authors:authors x :: acc
                      | _ -> acc) [] l in
  ({ authors;
     categories;
     contributors;
     generator;
     icon;
     id;
     links;
     logo;
     rights;
     subtitle;
     title;
     updated;
     entries; } : feed)

(* atomFeed =
     element atom:feed {
        atomCommonAttributes,
        (atomAuthor*
         & atomCategory*
         & atomContributor*
         & atomGenerator?
         & atomIcon?
         & atomId
         & atomLink*
         & atomLogo?
         & atomRights?
         & atomSubtitle?
         & atomTitle
         & atomUpdated
         & extensionElement * ),
        atomEntry*
      }
 *)
let feed_of_xml =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml a)));
    ("category", (fun ctx a -> `Category (category_of_xml a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml a)));
    ("generator", (fun ctx a -> `Generator (generator_of_xml a)));
    ("icon", (fun ctx a -> `Icon (icon_of_xml a)));
    ("id", (fun ctx a -> `ID (id_of_xml a)));
    ("link", (fun ctx a -> `Link (link_of_xml a)));
    ("logo", (fun ctx a -> `Logo (logo_of_xml a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml a)));
    ("subtitle", (fun ctx a -> `Subtitle (subtitle_of_xml a)));
    ("title", (fun ctx a -> `Title (title_of_xml a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml a)));
    ("entry", (fun ctx a -> `Entry a));
  ] in
  generate_catcher ~namespaces ~data_producer make_feed

let feed_of_xml' =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml' a)));
    ("category", (fun ctx a -> `Category (category_of_xml' a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml' a)));
    ("generator", (fun ctx a -> `Generator (generator_of_xml' a)));
    ("icon", (fun ctx a -> `Icon (icon_of_xml' a)));
    ("id", (fun ctx a -> `ID (id_of_xml' a)));
    ("link", (fun ctx a -> `Link (link_of_xml' a)));
    ("logo", (fun ctx a -> `Logo (logo_of_xml' a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml' a)));
    ("subtitle", (fun ctx a -> `Subtitle (subtitle_of_xml' a)));
    ("title", (fun ctx a -> `Title (title_of_xml' a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml' a)));
    ("entry", (fun ctx a -> `Entry (entry_of_xml' a)));
  ] in
  generate_catcher ~namespaces ~data_producer (fun x -> x)

let parse input =
  match XML.of_xmlm input |> snd with
  | XML.Node (tag, datas) when tag_is tag "feed" -> feed_of_xml (tag, datas)
  | _ -> Error.raise_expectation (Error.Tag "feed") Error.Root
(* FIXME: the spec says that an entry can appear as the top-level element *)

let unsafe input =
  match XML.of_xmlm input |> snd with
  | XML.Node (tag, datas) when tag_is tag "feed" ->
     `Feed (feed_of_xml' (tag, datas))
  | _ -> `Feed []



(* Conversion to XML
 ***********************************************************************)

(* Tag with the Atom namespace *)
let atom name : Xmlm.tag = ((atom_ns, name), [])

let text_construct_to_xml tag_name (t: text_construct) =
  match t with
  | Text t ->
     XML.Node(((atom_ns, tag_name), [("", "type"), "text"]), [XML.Data t])
  | Html t ->
     XML.Node(((atom_ns, tag_name), [("", "type"), "html"]), [XML.Data t])
  | Xhtml x ->
     let div = XML.Node(((xhtml_ns, "div"), [("", "xmlns"), xhtml_ns]), x) in
     XML.Node(((atom_ns, tag_name), [("", "type"), "xhtml"]), [div])

let person_to_xml name (a: author) =
  XML.Node(atom name, [node_data (atom "name") a.name]
                      |> add_node_uri (atom "uri") a.uri
                      |> add_node_data (atom "email") a.email)

let author_to_xml a = person_to_xml "author" a
let contributor_to_xml a = person_to_xml "contributor" a

let category_to_xml (c: category) =
  XML.Node(atom "category", [node_data (tag "term") c.term]
                            |> add_node_uri (tag "scheme") c.scheme
                            |> add_node_data (tag "label") c.label)

let generator_to_xml (g: generator) =
  let attr = [] |> add_attr ("", "version") g.version
             |> add_attr_uri ("", "uri") g.uri in
  XML.Node(((atom_ns, "generator"), attr), [XML.Data g.content])

let string_of_rel = function
  | Alternate -> "alternate"
  | Related -> "related"
  | Self -> "self"
  | Enclosure -> "enclosure"
  | Via -> "via"
  | Link l -> uri_to_string l

let link_to_xml (l: link) =
  let attr = [("", "href"), uri_to_string l.href;
              ("", "rel"), string_of_rel l.rel ]
             |> add_attr ("", "type") l.type_media
             |> add_attr ("", "hreflang") l.hreflang
             |> add_attr ("", "title") l.title in
  let attr = match l.length with
    | Some len -> (("", "length"), string_of_int len) :: attr
    | None -> attr in
  XML.Node(((atom_ns, "link"), attr), [])

let string_of_date d =
  (* Example: 2014-03-19T15:51:25.050-07:00 *)
  CalendarLib.Printer.Calendar.sprint "%Y-%0m-%0dT%0H:%0M:%0S%:z" d

let add_node_date tag date nodes =
  match date with
  | None -> nodes
  | Some d -> node_data tag (string_of_date d) :: nodes

let source_to_xml (s: source) =
  let (a0, a) = s.authors in
  let (l0, l) = s.links in
  let nodes =
    [author_to_xml a0;
     node_data (atom "id") (uri_to_string s.id);
     link_to_xml l0;
     text_construct_to_xml "title" s.title ]
    |> add_nodes_map author_to_xml a
    |> add_nodes_map category_to_xml s.categories
    |> add_nodes_map contributor_to_xml s.contributors
    |> add_node_option generator_to_xml s.generator
    |> add_node_option (node_uri (atom "icon")) s.icon
    |> add_nodes_map link_to_xml l
    |> add_node_option (node_uri (atom "logo")) s.logo
    |> add_node_option (text_construct_to_xml "rights") s.rights
    |> add_node_option (text_construct_to_xml "subtitle") s.subtitle
    |> add_node_date (atom "updated") s.updated in
  XML.Node(atom "source", nodes)

let content_to_xml (c: content) =
  match c with
  | Text t ->
     XML.Node(((atom_ns, "content"), [("", "type"), "text"]), [XML.Data t])
  | Html t ->
     XML.Node(((atom_ns, "content"), [("", "type"), "html"]), [XML.Data t])
  | Xhtml x ->
     let div = XML.Node(((xhtml_ns, "div"), [("", "xmlns"), xhtml_ns]), x) in
     XML.Node(((atom_ns, "content"), [("", "type"), "xhtml"]), [div])
  | Mime(mime, d) ->
     XML.Node(((atom_ns, "content"), [("", "type"), mime]), [XML.Data d])
  | Src(mime, uri) ->
     let attr = [ ("", "src"), uri_to_string uri ]
                |> add_attr ("", "type") mime in
     XML.Node(((atom_ns, "content"), attr), [])

let entry_to_xml (e: entry) =
  let (a0, a) = e.authors in
  let nodes =
    [author_to_xml a0;
     node_data (atom "id") (uri_to_string e.id);
     text_construct_to_xml "title" e.title;
     node_data (atom "updated") (string_of_date e.updated) ]
    |> add_nodes_map author_to_xml a
    |> add_nodes_map category_to_xml e.categories
    |> add_node_option content_to_xml e.content
    |> add_nodes_map contributor_to_xml e.contributors
    |> add_nodes_map link_to_xml e.links
    |> add_node_date (atom "published") e.published
    |> add_node_option (text_construct_to_xml "rights") e.rights
    |> add_nodes_map source_to_xml e.sources
    |> add_node_option (text_construct_to_xml "summary") e.summary in
  XML.Node(atom "entry", nodes)

let to_xml (f: feed) =
  let nodes =
    (node_data (atom "id") (uri_to_string f.id)
     :: text_construct_to_xml "title" f.title
     :: node_data (atom "updated") (string_of_date f.updated)
     :: List.map author_to_xml f.authors)
    |> add_nodes_map category_to_xml f.categories
    |> add_nodes_map contributor_to_xml f.contributors
    |> add_node_option generator_to_xml f.generator
    |> add_node_option (node_uri (atom "icon")) f.icon
    |> add_nodes_map link_to_xml f.links
    |> add_node_option (node_uri (atom "logo")) f.logo
    |> add_node_option (text_construct_to_xml "rights") f.rights
    |> add_node_option (text_construct_to_xml "subtitle") f.subtitle
    |> add_nodes_map entry_to_xml f.entries in
  XML.Node(((atom_ns, "feed"), [("", "xmlns"), atom_ns]), nodes)


(* Atom and XHTML have been declared well in the above XML
   representation.  One can remove them. *)
let output_ns_prefix s =
  if s = atom_ns || s = xhtml_ns then Some "" else None

let output feed dest =
  let o = Xmlm.make_output dest ~decl:true ~ns_prefix:output_ns_prefix in
  XML.to_xmlm (to_xml feed) o
