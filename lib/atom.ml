open Common.XML
open Common.Util

(** {C See RFC 4287 § 3.2}
  * A Person construct is an element that describes a person,
  * corporation, or similar entity (hereafter, 'person').
  *
  * atomPersonConstruct =
  *    atomCommonAttributes,
  *    (element atom:name { text } {% \equiv %} [`Name]
  *     & element atom:uri { atomUri }? {% \equiv %} [`URI]
  *     & element atom:email { atomEmailAddress }? {% \equiv %} [`Email]
  *     & extensionElement* )
  *
  * This specification assigns no significance to the order of appearance
  * of the child elements in a Person construct.  Person constructs allow
  * extension Metadata elements (see Section 6.4).
  *
  * {C See RFC 4287 § 4.2.1}
  * The "atom:author" element is a Person construct that indicates the
  * author of the entry or feed.
  *
  * atomAuthor = element atom:author { atomPersonConstruct }
  *
  * If an atom:entry element does not contain atom:author elements, then
  * the atom:author elements of the contained atom:source element are
  * considered to apply.  In an Atom Feed Document, the atom:author
  * elements of the containing atom:feed element are considered to apply
  * to the entry if there are no atom:author elements in the locations
  * described above.
*)

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

let make_author (l : [< author'] list) =
  (** element atom:name { text } *)
  let name = match find (function `Name _ -> true | _ -> false) l with
    | Some (`Name s) -> s
    | _ -> Common.Error.raise_expectation
             (Common.Error.Tag "name")
             (Common.Error.Tag "author")
  in
  (** element atom:uri { atomUri }? *)
  let uri = match find (function `URI _ -> true | _ -> false) l with
    | Some (`URI u) -> Some u
    | _ -> None
  in
  (** element atom:email { atomEmailAddress }? *)
  let email = match find (function `Email _ -> true | _ -> false) l with
    | Some (`Email e) -> Some e
    | _ -> None
  in
  ({ name; uri; email; } : author)

let author_name_of_xml (tag, datas) =
  try get_leaf datas
  with Common.Error.Expected_Leaf -> "" (* mandatory ? *)

let author_uri_of_xml (tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Common.Error.Expected_Leaf ->
    Common.Error.raise_expectation
      Common.Error.Data
      (Common.Error.Tag "author/uri")

let author_email_of_xml (tag, datas) =
  try get_leaf datas
  with Common.Error.Expected_Leaf -> "" (* mandatory ? *)

let author_uri_of_xml' =
  let leaf_producer ctx data = `URI (Uri.of_string data) in
  generate_catcher ~leaf_producer (fun x -> List.hd x)
let author_name_of_xml' =
  let leaf_producer ctx data = `Name (Uri.of_string data) in
  generate_catcher ~leaf_producer (fun x -> List.hd x)
let author_email_of_xml' =
  let leaf_producer ctx data = `Email (Uri.of_string data) in
  generate_catcher ~leaf_producer (fun x -> List.hd x)

(** Safe generator *)

let author_of_xml =
  let data_producer = [
    ("name", (fun ctx a -> `Name (author_name_of_xml a)));
    ("uri", (fun ctx a -> `URI (author_uri_of_xml a)));
    ("email", (fun ctx a -> `Email (author_email_of_xml a)));
  ] in
  generate_catcher ~data_producer make_author

(** Unsafe generator *)

let author_of_xml' =
  let data_producer = [
    ("name", (fun ctx a -> author_name_of_xml' a));
    ("uri", (fun ctx a -> author_uri_of_xml' a));
    ("email", (fun ctx a -> author_email_of_xml' a));
  ] in
  generate_catcher ~data_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.2 }
  * The "atom:category" element conveys information about a category
  * associated with an entry or feed.  This specification assigns no
  * meaning to the content (if any) of this element.
  *
  * atomCategory =
  *    element atom:category {
  *       atomCommonAttributes,
  *       attribute term { text }, {% \equiv %} [`Term]
  *       attribute scheme { atomUri }?, {% \equiv %} [`Scheme]
  *       attribute label { text }?, {% \equiv %} [`Label]
  *       undefinedContent
  *    }
  *
  * {C See RFC 4287 § 4.2.2.1 }
  * The "term" attribute is a string that identifies the category to
  * which the entry or feed belongs.  Category elements MUST have a
  * "term" attribute.
  *
  * {C See RFC 4287 § 4.2.2.2 }
  * The "scheme" attribute is an IRI that identifies a categorization
  * scheme.  Category elements MAY have a "scheme" attribute.
  *
  * {C See RFC 4287 § 4.2.2.3 }
  * The "label" attribute provides a human-readable label for display in
  * end-user applications.  The content of the "label" attribute is
  * Language-Sensitive.  Entities such as "&amp;" and "&lt;" represent
  * their corresponding characters ("&" and "<", respectively), not
  * markup.  Category elements MAY have a "label" attribute.
*)

type category =
  {
    term: string;
    scheme: Uri.t option;
    label: string option;
  }

type category' = [
  | `Term of string
  | `Scheme of Uri.t
  | `Label of string
]

let make_category (l : [< category'] list) =
  (** attribute term { text } *)
  let term = match find (function `Term _ -> true | _ -> false) l with
    | Some (`Term t) -> t
    | _ -> Common.Error.raise_expectation
             (Common.Error.Attr "term")
             (Common.Error.Tag "category")
  in
  (** attribute scheme { atomUri }? *)
  let scheme =
    match find (function `Scheme _ -> true | _ -> false) l with
    | Some (`Scheme u) -> Some u
    | _ -> None
  in
  (** attribute label { text }? *)
  let label = match find (function `Label _ -> true | _ -> false) l with
    | Some (`Label l) -> Some l
    | _ -> None
  in
  ({ term; scheme; label; } : category)

(** Safe generator, Unsafe generator *)

let category_of_xml, category_of_xml' =
  let attr_producer = [
    ("term", (fun ctx a -> `Term a));
    ("scheme", (fun ctx a -> `Scheme (Uri.of_string a)));
    ("label", (fun ctx a -> `Label a))
  ] in
  generate_catcher ~attr_producer make_category,
  generate_catcher ~attr_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.3 }
  * The "atom:contributor" element is a Person construct that indicates a
  * person or other entity who contributed to the entry or feed.
  *
  * atomContributor = element atom:contributor { atomPersonConstruct }
*)

let make_contributor = make_author
let contributor_of_xml = author_of_xml
let contributor_of_xml' = author_of_xml'

(** {C See RFC 4287 § 4.2.4 }
  * The "atom:generator" element's content identifies the agent used to
  * generate a feed, for debugging and other purposes.
  *
  * atomGenerator = element atom:generator {
  *    atomCommonAttributes,
  *    attribute uri { atomUri }?, {% \equiv %} [`URI]
  *    attribute version { text }?, {% \equiv %} [`Version]
  *    text {% \equiv %} [`Content]
  * }
  *
  * The content of this element, when present, MUST be a string that is a
  * human-readable name for the generating agent.  Entities such as
  * "&amp;" and "&lt;" represent their corresponding characters ("&" and
  * "<" respectively), not markup.
  *
  * The atom:generator element MAY have a "uri" attribute whose value
  * MUST be an IRI reference [RFC3987].  When dereferenced, the resulting
  * URI (mapped from an IRI, if necessary) SHOULD produce a
  * representation that is relevant to that agent.
  *
  * The atom:generator element MAY have a "version" attribute that
  * indicates the version of the generating agent.
*)

type generator =
  {
    version: string option;
    uri: Uri.t option;
    content: string;
  }

type generator' = [
  | `URI of Uri.t
  | `Version of string
  | `Content of string
]

let make_generator (l : [< generator'] list) =
  (** text *)
  let content = match find (function `Content _ -> true | _ -> false) l with
    | Some ((`Content c)) -> c
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "generator")
  in
  (** attribute version { text }? *)
  let version = match find (function `Version _ -> true | _ -> false) l with
    | Some ((`Version v)) -> Some v
    | _ -> None
  in
  (** attribute uri { atomUri }? *)
  let uri = match find (function `URI _ -> true | _ -> false) l with
    | Some ((`URI u)) -> Some u
    | _ -> None
  in ({ version; uri; content; } : generator)

(** Safe generator, Unsafe generator *)

let generator_of_xml, generator_of_xml' =
  let attr_producer = [
    ("version", (fun ctx a -> `Version a));
    ("uri", (fun ctx a -> `URI (Uri.of_string a)));
  ] in
  let leaf_producer ctx data = `Content data in
  generate_catcher ~attr_producer ~leaf_producer make_generator,
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.5 }
  * The "atom:icon" element's content is an IRI reference [RFC3987] that
  * identifies an image that provides iconic visual identification for a
  * feed.
  *
  * atomIcon = element atom:icon {
  *    atomCommonAttributes,
  *    (atomUri) {% \equiv %} [`URI]
  * }
  *
  * The image SHOULD have an aspect ratio of one (horizontal) to one
  * (vertical) and SHOULD be suitable for presentation at a small size.
*)

type icon = Uri.t
type icon' = [ `URI of Uri.t ]

let make_icon (l : [< icon'] list) =
  (** (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> u
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "icon")
  in uri

(** Safe generator, Unsafe generator *)

let icon_of_xml, icon_of_xml' =
  let leaf_producer ctx data = `URI (Uri.of_string data) in
  generate_catcher ~leaf_producer make_icon,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.6 }
  * The "atom:id" element conveys a permanent, universally unique
  * identifier for an entry or feed.
  *
  * atomId = element atom:id {
  *    atomCommonAttributes,
  *    (atomUri) {% \equiv %} [`URI]
  * }
  *
  * Its content MUST be an IRI, as defined by [RFC3987].  Note that the
  * definition of "IRI" excludes relative references.  Though the IRI
  * might use a dereferencable scheme, Atom Processors MUST NOT assume it
  * can be dereferenced.
  *
  * There is more information in the RFC but they are not necessary here
  * - at least, they can not be checked here.
*)

type id = Uri.t
type id' = [ `URI of Uri.t ]

let make_id (l : [< id'] list) =
  (** (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> u
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "id")
  in uri

let id_of_xml, id_of_xml' =
  let leaf_producer ctx data = `URI (Uri.of_string data) in
  generate_catcher ~leaf_producer make_id,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.7 }
  * The "atom:link" element defines a reference from an entry or feed to
  * a Web resource.  This specification assigns no meaning to the content
  * (if any) of this element.
  *
  * atomLink =
  *    element atom:link {
  *       atomCommonAttributes,
  *       attribute href { atomUri }, {% \equiv %} [`HREF]
  *       attribute rel { atomNCName | atomUri }?, {% \equiv %} [`Rel]
  *       attribute type { atomMediaType }?, {% \equiv %} [`Type]
  *       attribute hreflang { atomLanguageTag }?, {% \equiv %} [`HREFLang]
  *       attribute title { text }?, {% \equiv %} [`Title]
  *       attribute length { text }?, {% \equiv %} [`Length]
  *       undefinedContent
  *    }
  *
  * {C See RFC 4287 § 4.2.7.1 }
  * The "href" attribute contains the link's IRI. atom:link elements MUST
  * have an href attribute, whose value MUST be a IRI reference
  * [RFC3987].
  *
  * {C See RFC 4287 § 4.2.7.2 }
  * atom:link elements MAY have a "rel" attribute that indicates the link
  * relation type. {b If the "rel" attribute is not present, the link
  * element MUST be interpreted as if the link relation type is
  * "alternate".}
  *
  * {b The value of "rel" MUST be a string that is non-empty and matches
  * either the "isegment-nz-nc" or the "IRI" production in [RFC3987].}
  * Note that use of a relative reference other than a simple name is not
  * allowed.  If a name is given, implementations MUST consider the link
  * relation type equivalent to the same name registered within the IANA
  *
  * {C See RFC 4287 § 4.2.7.3 }
  * On the link element, the "type" attribute's value is an advisory
  * media type: it is a hint about the type of the representation that is
  * expected to be returned when the value of the href attribute is
  * dereferenced.  Note that the type attribute does not override the
  * actual media type returned with the representation.  Link elements
  * MAY have a type attribute, whose value MUST conform to the syntax of
  * a MIME media type [MIMEREG].
  *
  * {C See RFC 4287 § 4.2.7.4 }
  * The "hreflang" attribute's content describes the language of the
  * resource pointed to by the href attribute.  When used together with
  * the rel="alternate", it implies a translated version of the entry.
  * Link elements MAY have an hreflang attribute, whose value MUST be a
  * language tag [RFC3066].
  *
  * {C See RFC 4287 § 4.2.7.5 }
  * The "title" attribute conveys human-readable information about the
  * link.  The content of the "title" attribute is Language-Sensitive.
  * Entities such as "&amp;" and "&lt;" represent their corresponding
  * characters ("&" and "<", respectively), not markup.  Link elements
  * MAY have a title attribute.
  *
  * {C See RFC 4287 § 4.2.7.6 }
  * The "length" attribute indicates an advisory length of the linked
  * content in octets; it is a hint about the content length of the
  * representation returned when the IRI in the href attribute is mapped
  * to a URI and dereferenced.  Note that the length attribute does not
  * override the actual content length of the representation as reported
  * by the underlying protocol.  Link elements MAY have a length
  * attribute.
*)

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
  | `HREF of Uri.t
  | `Rel of rel
  | `Type of string
  | `HREFLang of string
  | `Title of string
  | `Length of int
]

let make_link (l : [< link'] list) =
  (** attribute href { atomUri } *)
  let href = match find (function `HREF _ -> true | _ -> false) l with
    | Some (`HREF u) -> u
    | _ -> Common.Error.raise_expectation
             (Common.Error.Attr "href")
             (Common.Error.Tag "link")
  in
  (** attribute rel { atomNCName | atomUri }? *)
  let rel = match find (function `Rel _ -> true | _ -> false) l with
    | Some (`Rel r) -> r
    | _ -> Alternate (* cf. RFC 4287 § 4.2.7.2 *)
  in
  (** attribute type { atomMediaType }? *)
  let type_media = match find (function `Type _ -> true | _ -> false) l with
    | Some (`Type t) -> Some t
    | _ -> None
  in
  (** attribute hreflang { atomLanguageTag }? *)
  let hreflang =
    match find (function `HREFLang _ -> true | _ -> false) l with
    | Some (`HREFLang l) -> Some l
    | _ -> None
  in
  (** attribute title { text }? *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title s) -> Some s
    | _ -> None
  in
  (** attribute length { text }? *)
  let length = match find (function `Length _ -> true | _ -> false) l with
    | Some (`Length i) -> Some i
    | _ -> None
  in
  ({ href; rel; type_media; hreflang; title; length; } : link)

let rel_of_string s = match String.lowercase (String.trim s) with
  | "alternate" -> Alternate
  | "related" -> Related
  | "self" -> Self
  | "enclosure" -> Enclosure
  | "via" -> Via
  | uri -> Link (Uri.of_string uri) (* RFC 4287 § 4.2.7.2 *)

(** Safe generator, Unsafe generator *)

let link_of_xml, link_of_xml' =
  let attr_producer = [
    ("href", (fun ctx a -> `HREF (Uri.of_string a)));
    ("rel", (fun ctx a -> `Rel (rel_of_string a)));
    ("type", (fun ctx a -> `Type a));
    ("hreflang", (fun ctx a -> `HREFLang a));
    ("title", (fun ctx a -> `Title a));
    ("length", (fun ctx a -> `Length (int_of_string a)));
  ] in
  generate_catcher ~attr_producer make_link,
  generate_catcher ~attr_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.8 }
  * The "atom:logo" element's content is an IRI reference [RFC3987] that
  * identifies an image that provides visual identification for a feed.
  *
  * atomLogo = element atom:logo {
  *    atomCommonAttributes,
  *    (atomUri) {% \equiv %} [`URI]
  * }
  *
  * The image SHOULD have an aspect ratio of 2 (horizontal) to 1
  * (vertical).
*)

type logo = Uri.t
type logo' = [ `URI of Uri.t ]

let make_logo (l : [< logo'] list) =
  (** (atomUri) *)
  let uri = match find (fun (`URI _) -> true) l with
    | Some (`URI u) -> u
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "logo")
  in uri

(** Safe generator, Unsafe generator *)

let logo_of_xml, logo_of_xml' =
  let leaf_producer ctx data = `URI (Uri.of_string data) in
  generate_catcher ~leaf_producer make_logo,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.9 }
  *
  * The "atom:published" element is a Date construct indicating an
  * instant in time associated with an event early in the life cycle of
  * the entry.
  *
  * atomPublished = element atom:published { atomDateConstruct } {% \equiv %}
  * [`Date]
  *
  * Typically, atom:published will be associated with the initial
  * creation or first availability of the resource.
*)

type published = Netdate.t
type published' = [ `Date of Netdate.t ]

let make_published (l : [< published'] list) =
  (** atom:published { atomDateConstruct } *)
  let date = match find (fun (`Date _) -> true) l with
    | Some (`Date d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "published")
  in date

(** Safe generator, Unsafe generator *)

let published_of_xml, published_of_xml' =
  let leaf_producer ctx data = `Date (Netdate.parse data) in
  generate_catcher ~leaf_producer make_published,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.10 }
  * The "atom:rights" element is a Text construct that conveys
  * information about rights held in and over an entry or feed.
  *
  * atomRights = element atom:rights { atomTextConstruct } {% \equiv %} [`Data]
  *
  * The atom:rights element SHOULD NOT be used to convey machine-readable
  * licensing information.
  *
  * If an atom:entry element does not contain an atom:rights element,
  * then the atom:rights element of the containing atom:feed element, if
  * present, is considered to apply to the entry.
*)

type rights = string
type rights' = [ `Data of string ]

let make_rights (l : [< rights'] list) =
  (** element atom:rights { atomTextConstruct } *)
  let rights = match find (fun (`Data _) -> true) l with
    | Some (`Data d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "rights")
  in rights

(** Safe generator, Unsafe generator *)

let rights_of_xml, rights_of_xml' =
  let leaf_producer ctx data = `Data data in
  generate_catcher ~leaf_producer make_rights,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.14 }
  * The "atom:title" element is a Text construct that conveys a human-
  * readable title for an entry or feed.
  *
  * atomTitle = element atom:title { atomTextConstruct } {% \equiv %} [`Data]
*)

type title = string
type title' = [ `Data of string ]

let make_title (l : [< title'] list) =
  (** element atom:title { atomTextConstruct } *)
  let title = match find (fun (`Data _) -> true) l with
    | Some (`Data d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "title")
  in title

(** Safe generator, Unsafe generator *)

let title_of_xml, title_of_xml' =
  let leaf_producer ctx data = `Data data in
  generate_catcher ~leaf_producer make_title,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.12 }
  * The "atom:subtitle" element is a Text construct that conveys a human-
  * readable description or subtitle for a feed.
  *
  * atomSubtitle = element atom:subtitle { atomTextConstruct } {% \equiv %}
  * [`Data]
*)

type subtitle = string
type subtitle' = [ `Data of string ]

let make_subtitle (l : [< subtitle'] list) =
  let subtitle = match find (fun (`Data _) -> true) l with
    | Some (`Data d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "subtitle")
  in subtitle

(** Safe generator, Unsafe generator *)

let subtitle_of_xml, subtitle_of_xml' =
  let leaf_producer ctx data = `Data data in
  generate_catcher ~leaf_producer make_subtitle,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.15 }
  * The "atom:updated" element is a Date construct indicating the most
  * recent instant in time when an entry or feed was modified in a way
  * the publisher considers significant.  Therefore, not all
  * modifications necessarily result in a changed atom:updated value.
  *
  * atomUpdated = element atom:updated { atomDateConstruct } {% \equiv %}
  * [`Date]
  *
  * Publishers MAY change the value of this element over time.
*)

type updated = Netdate.t
type updated' = [ `Date of Netdate.t ]

let make_updated (l : [< updated'] list) =
  (** atom:updated { atomDateConstruct } *)
  let updated = match find (fun (`Date _) -> true) l with
    | Some (`Date d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "updated")
  in updated

(** Safe generator, Unsafe generator *)

let updated_of_xml, updated_of_xml' =
  let leaf_producer ctx data = `Date (Netdate.parse data) in
  generate_catcher ~leaf_producer make_updated,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.11 }
  * If an atom:entry is copied from one feed into another feed, then the
  * source atom:feed's metadata (all child elements of atom:feed other
  * than the atom:entry elements) MAY be preserved within the copied
  * entry by adding an atom:source child element, if it is not already
  * present in the entry, and including some or all of the source feed's
  * Metadata elements as the atom:source element's children.  Such
  * metadata SHOULD be preserved if the source atom:feed contains any of
  * the child elements atom:author, atom:contributor, atom:rights, or
  * atom:category and those child elements are not present in the source
  * atom:entry.
  *
  * atomSource =
  *    element atom:source {
  *       atomCommonAttributes,
  *       (atomAuthor* {% \equiv %} [`Author]
  *        & atomCategory* {% \equiv %} [`Category]
  *        & atomContributor* {% \equiv %} [`Contributor]
  *        & atomGenerator? {% \equiv %} [`Generator]
  *        & atomIcon? {% \equiv %} [`Icon]
  *        & atomId? {% \equiv %} [`ID]
  *        & atomLink* {% \equiv %} [`Link]
  *        & atomLogo? {% \equiv %} [`Logo]
  *        & atomRights? {% \equiv %} [`Rights]
  *        & atomSubtitle? {% \equiv %} [`Subtitle]
  *        & atomTitle? {% \equiv %} [`Title]
  *        & atomUpdated? {% \equiv %} [`Updated]
  *        & extensionElement* )
  *    }
  *
  * The atom:source element is designed to allow the aggregation of
  * entries from different feeds while retaining information about an
  * entry's source feed.  For this reason, Atom Processors that are
  * performing such aggregation SHOULD include at least the required
  * feed-level Metadata elements (atom:id, atom:title, and atom:updated)
  * in the atom:source element.
  *
  * See RFC 4287 § 4.1.2 for more details.
*)

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

let make_source (l : [< source'] list) =
  (** atomAuthor* *)
  let authors =
    (function
      | [] -> Common.Error.raise_expectation
                (Common.Error.Tag "author")
                (Common.Error.Tag "source")
      | x :: r -> x, r)
      (List.fold_left
         (fun acc -> function `Author x -> x :: acc | _ -> acc)
         [] l)
  in
  (** atomCategory* *)
  let categories =
    List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc)
      [] l in
  (** atomContributor* *)
  let contributors =
    List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc)
      [] l in
  (** atomGenerator? *)
  let generator =
    match find (function `Generator _ -> true | _ -> false) l with
    | Some (`Generator g) -> Some g
    | _ -> None
  in
  (** atomIcon? *)
  let icon = match find (function `Icon _ -> true | _ -> false) l with
    | Some (`Icon u) -> Some u
    | _ -> None
  in
  (** atomId? *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Common.Error.raise_expectation
             (Common.Error.Tag "id")
             (Common.Error.Tag "source")
  in
  (** atomLink* *)
  let links =
    (function
      | [] -> Common.Error.raise_expectation
                (Common.Error.Tag "link")
                (Common.Error.Tag "source")
      | x :: r -> (x, r))
      (List.fold_left (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l)
  in
  (** atomLogo? *)
  let logo = match find (function `Logo _ -> true | _ -> false) l with
    | Some (`Logo u) -> Some u
    | _ -> None
  in
  (** atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None
  in
  (** atomSubtitle? *)
  let subtitle = match find (function `Subtitle _ -> true | _ -> false) l with
    | Some (`Subtitle s) -> Some s
    | _ -> None
  in
  (** atomTitle? *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title s) -> s
    | _ -> Common.Error.raise_expectation
             (Common.Error.Tag "title")
             (Common.Error.Tag "source")
  in
  (** atomUpdated? *)
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

(** Safe generator *)

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
  generate_catcher ~data_producer make_source

(** Unsafe generator *)

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
  generate_catcher ~data_producer (fun x -> x)

(** {C See RFC 4287 § 3.1.1 }
  * Text constructs MAY have a "type" attribute.  When present, the value
  * MUST be one of [Text], [Html], or [Xhtml].  If the "type" attribute
  * is not provided, Atom Processors MUST behave as though it were
  * present with a value of "text".  Unlike the atom:content element
  * defined in Section 4.1.3, MIME media types [MIMEREG] MUST NOT be used
  * as values for the "type" attribute on Text constructs.
  *
  * {C See RFC 4287 § 4.1.3.1 }
  * On the atom:content element, the value of the "type" attribute MAY be
  * one of "text", "html", or "xhtml".  Failing that, it MUST conform to
  * the syntax of a MIME media type, but MUST NOT be a composite type
  * (see Section 4.2.6 of [MIMEREG]).  If neither the type attribute nor
  * the src attribute is provided, Atom Processors MUST behave as though
  * the type attribute were present with a value of "text".
*)

type type_content =
  | Html
  | Text
  | Xhtml
  | Mime of string

let type_content_of_string s = match String.lowercase (String.trim s) with
  | "html" -> Html
  | "text" -> Text
  | "xhtml" -> Xhtml
  | mime -> Mime mime

(** {C See RFC 4287 § 4.1.3 }
  * The "atom:content" element either contains or links to the content of
  * the entry.  The content of atom:content is Language-Sensitive.
  *
  * atomInlineTextContent =
  *    element atom:content {
  *       atomCommonAttributes,
  *       attribute type { "text" | "html" }?, {% \equiv %} [`Type]
  *       (text)* {% \equiv %} [`Data]
  *    }
  *
  * atomInlineXHTMLContent =
  *    element atom:content {
  *       atomCommonAttributes,
  *       attribute type { "xhtml" }, {% \equiv %} [`Type]
  *       xhtmlDiv {% \equiv %} [`Data]
  *    }
  *
  * atomInlineOtherContent =
  *    element atom:content {
  *       atomCommonAttributes,
  *       attribute type { atomMediaType }?, {% \equiv %} [`Type]
  *       (text|anyElement)* {% \equiv %} [`Data]
  *    }
  *
  * atomOutOfLineContent =
  *    element atom:content {
  *       atomCommonAttributes,
  *       attribute type { atomMediaType }?, {% \equiv %} [`Type]
  *       attribute src { atomUri }, {% \equiv %} [`SRC]
  *       empty
  *    }
  *
  * atomContent = atomInlineTextContent
  *  | atomInlineXHTMLContent
  *  | atomInlineOtherContent
  *  | atomOutOfLineContent
  *
  * {C See RFC 4287 § 4.1.3.2 }
  * atom:content MAY have a "src" attribute, whose value MUST be an IRI
  * reference [RFC3987].  If the "src" attribute is present, atom:content
  * MUST be empty.  Atom Processors MAY use the IRI to retrieve the
  * content and MAY choose to ignore remote content or to present it in a
  * different manner than local content.

  * If the "src" attribute is present, the "type" attribute SHOULD be
  * provided and MUST be a MIME media type [MIMEREG], rather than "text",
  * "html", or "xhtml".  The value is advisory; that is to say, when the
  * corresponding URI (mapped from an IRI, if necessary) is dereferenced,
  * if the server providing that content also provides a media type, the
  * server-provided media type is authoritative.
*)

type content =
  {
    ty : type_content;
    src : Uri.t option;
    data : string;
  }

type content' = [
  | `Type of type_content
  | `SRC of Uri.t
  | `Data of string
]

(* TODO: see RFC *)

let make_content (l : [< content'] list) =
  (** attribute type { "text" | "html" }?
   *  | attribute type { "xhtml" }
   *  | attribute type { atomMediaType }? *)
  let ty = match find (function `Type _ -> true | _ -> false) l with
    | Some (`Type ty) -> ty
    | _ -> Text
  in
  (** attribute src { atomUri }
   *  | none *)
  let src = match find (function `SRC _ -> true | _ -> false) l with
    | Some (`SRC s) -> Some s
    | _ -> None
  in
  (** (text)*
   *  | xhtmlDiv
   *  | (text|anyElement)*
   *  | none *)
  let data = match find (function `Data _ -> true | _ -> false) l with
    | Some (`Data d) -> d
    | _ -> ""
  in
  ({ ty; src; data; } : content)

(** Safe generator, Unsafe generator *)

let content_of_xml, content_of_xml' =
  let attr_producer = [
    ("type", (fun ctx a -> `Type (type_content_of_string a)));
    ("src", (fun ctx a -> `SRC (Uri.of_string a)));
  ] in
  let leaf_producer ctx data = `Data data in
  generate_catcher ~attr_producer ~leaf_producer make_content,
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.2.13 }
  * The "atom:summary" element is a Text construct that conveys a short
  * summary, abstract, or excerpt of an entry.
  *
  * atomSummary = element atom:summary { atomTextConstruct } {% \equiv %}
  * [`Data]
  *
  * It is not advisable for the atom:summary element to duplicate
  * atom:title or atom:content because Atom Processors might assume there
  * is a useful summary when there is none.
*)

type summary = string
type summary' = [ `Data of string ]

let make_summary (l : [< summary'] list) =
  (** element atom:summaru { atomTextConstruct } *)
  let data = match find (fun (`Data _) -> true) l with
    | Some (`Data d) -> d
    | _ -> Common.Error.raise_expectation
             Common.Error.Data
             (Common.Error.Tag "summary")
  in data

(** Safe generator, Unsafe generator *)

let summary_of_xml, summary_of_xml' =
  let leaf_producer ctx data = `Data data in
  generate_catcher ~leaf_producer make_summary,
  generate_catcher ~leaf_producer (fun x -> x)

(** {C See RFC 4287 § 4.1.2 }
  * The "atom:entry" element represents an individual entry, acting as a
  * container for metadata and data associated with the entry.  This
  * element can appear as a child of the atom:feed element, or it can
  * appear as the document (i.e., top-level) element of a stand-alone
  * Atom Entry Document.
  *
  * atomEntry =
  *    element atom:entry {
  *       atomCommonAttributes,
  *       (atomAuthor* {% \equiv %} [`Author]
  *        & atomCategory* {% \equiv %} [`Category]
  *        & atomContent? {% \equiv %} [`Content]
  *        & atomContributor* {% \equiv %} [`Contributor]
  *        & atomId {% \equiv %} [`ID]
  *        & atomLink* {% \equiv %} [`Link]
  *        & atomPublished? {% \equiv %} [`Published]
  *        & atomRights? {% \equiv %} [`Rights]
  *        & atomSource? {% \equiv %} [`Source]
  *        & atomSummary? {% \equiv %} [`Summary]
  *        & atomTitle {% \equiv %} [`Title]
  *        & atomUpdated {% \equiv %} [`Updated]
  *        & extensionElement* )
  *    }
  *
  * This specification assigns no significance to the order of appearance
  * of the child elements of atom:entry.
  *
  * The following child elements are defined by this specification (note
  * that it requires the presence of some of these elements):
  *
  * o  {b atom:entry elements MUST contain one or more atom:author elements,
  *    unless the atom:entry contains an atom:source element that
  *    contains an atom:author element or, in an Atom Feed Document, the
  *    atom:feed element contains an atom:author element itself.}
  * o  atom:entry elements MAY contain any number of atom:category
  *    elements.
  * o  atom:entry elements MUST NOT contain more than one atom:content
  *    element.
  * o  atom:entry elements MAY contain any number of atom:contributor
  *    elements.
  * o  atom:entry elements MUST contain exactly one atom:id element.
  * o  {b atom:entry elements that contain no child atom:content element
  *    MUST contain at least one atom:link element with a rel attribute
  *    value of "alternate".}
  * o  {b atom:entry elements MUST NOT contain more than one atom:link
  *    element with a rel attribute value of "alternate" that has the
  *    same combination of type and hreflang attribute values.}
  * o  atom:entry elements MAY contain additional atom:link elements
  *    beyond those described above.
  * o  atom:entry elements MUST NOT contain more than one atom:published
  *    element.
  * o  atom:entry elements MUST NOT contain more than one atom:rights
  *    element.
  * o  atom:entry elements MUST NOT contain more than one atom:source
  *    element.
  * o  atom:entry elements MUST contain an atom:summary element in either
  *    of the following cases:
  *    *  the atom:entry contains an atom:content that has a "src"
  *       attribute (and is thus empty).
  *    *  the atom:entry contains content that is encoded in Base64;
  *       i.e., the "type" attribute of atom:content is a MIME media type
  *       [MIMEREG], but is not an XML media type [RFC3023], does not
  *       begin with "text/", and does not end with "/xml" or "+xml".
  * o  atom:entry elements MUST NOT contain more than one atom:summary
  *    element.
  * o  atom:entry elements MUST contain exactly one atom:title element.
  * o  atom:entry elements MUST contain exactly one atom:updated element.
*)

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

module Error = struct
  include Common.Error

  exception Duplicate_Link of ((Uri.t * string * string) * (string * string))

  let raise_duplicate_link
      { href; type_media; hreflang; _}
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

let make_entry (feed : [< feed'] list) (l : [< entry'] list) =
  let feed_author =
    match find (function `Author _ -> true | _ -> false) feed with
    | Some (`Author a) -> Some a
    | _ -> None
    (** (atomAuthor* *)
  in let authors =
    (* default author is feed/author, see RFC 4287 § 4.1.2 *)
    (function
      | None, [] ->
        Error.raise_expectation
          (Error.Tag "author")
          (Error.Tag "entry")
      | Some a, [] -> a, []
      | _, x :: r -> x, r)
      (feed_author,
       List.fold_left
         (fun acc -> function `Author x -> x :: acc | _ -> acc)
         [] l)
      (** atomCategory* *)
  in let categories = List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc) [] l
      (** atomContributor* *)
  in let contributors = List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc) [] l in
  (** atomId *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Error.raise_expectation (Error.Tag "id") (Error.Tag "entry")
    (** atomLink* *)
  in let links = List.fold_left
      (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l in
  (** atomPublished? *)
  let published = match find (function `Published _ -> true | _ -> false) l with
    | Some (`Published s) -> Some s
    | _ -> None
  in
  (** atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None
    (** atomSource? *)
  in let sources = List.fold_left
      (fun acc -> function `Source x -> x :: acc | _ -> acc) [] l in
  (** atomContent? *)
  let content = match find (function `Content _ -> true | _ -> false) l with
    | Some (`Content c) -> Some c
    | _ -> None
  in
  (** atomSummary? *)
  let summary = match find (function `Summary _ -> true | _ -> false) l with
    | Some (`Summary s) -> Some s
    | _ -> None
  in
  (** atomTitle *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ -> Error.raise_expectation (Error.Tag "title") (Error.Tag "entry")
  in
  (** atomUpdated *)
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

(** Safe generator *)

let entry_of_xml feed =
  let data_producer = [
    ("author", (fun ctx a -> `Author (author_of_xml a)));
    ("category", (fun ctx a -> `Category (category_of_xml a)));
    ("contributor", (fun ctx a -> `Contributor (contributor_of_xml a)));
    ("id", (fun ctx a -> `ID (id_of_xml a)));
    ("link", (fun ctx a -> `Link (link_of_xml a)));
    ("published", (fun ctx a -> `Published (published_of_xml a)));
    ("rights", (fun ctx a -> `Rights (rights_of_xml a)));
    ("source", (fun ctx a -> `Source (source_of_xml a)));
    ("content", (fun ctx a -> `Content (content_of_xml a)));
    ("summary", (fun ctx a -> `Summary (summary_of_xml a)));
    ("title", (fun ctx a -> `Title (title_of_xml a)));
    ("updated", (fun ctx a -> `Updated (updated_of_xml a)));
  ] in
  generate_catcher ~data_producer (make_entry feed)

(** Unsafe generator *)

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
  generate_catcher ~data_producer (fun x -> x)

(** {C See RFC 4287 § 4.1.1 }
  * The "atom:feed" element is the document (i.e., top-level) element of
  * an Atom Feed Document, acting as a container for metadata and data
  * associated with the feed.  Its element children consist of metadata
  * elements followed by zero or more atom:entry child elements.
  *
  * atomFeed =
  *    element atom:feed {
  *       atomCommonAttributes,
  *       (atomAuthor* {% \equiv %} [`Author]
  *        & atomCategory* {% \equiv %} [`Category]
  *        & atomContributor* {% \equiv %} [`Contributor]
  *        & atomGenerator? {% \equiv %} [`Generator]
  *        & atomIcon? {% \equiv %} [`Icon]
  *        & atomId {% \equiv %} [`ID]
  *        & atomLink* {% \equiv %} [`Link]
  *        & atomLogo? {% \equiv %} [`Logo]
  *        & atomRights? {% \equiv %} [`Rights]
  *        & atomSubtitle? {% \equiv %} [`Subtitle]
  *        & atomTitle {% \equiv %} [`Title]
  *        & atomUpdated {% \equiv %} [`Updated]
  *        & extensionElement* ),
  *       atomEntry* {% \equiv %} [`Entry]
  *    }
  *
  * This specification assigns no significance to the order of atom:entry
  * elements within the feed.
  *
  * The following child elements are defined by this specification (note
  * that the presence of some of these elements is required):
  *
  * o  atom:feed elements MUST contain one or more atom:author elements,
  *    unless all of the atom:feed element's child atom:entry elements
  *    contain at least one atom:author element.
  * o  atom:feed elements MAY contain any number of atom:category
  *    elements.
  * o  atom:feed elements MAY contain any number of atom:contributor
  *    elements.
  * o  atom:feed elements MUST NOT contain more than one atom:generator
  *    element.
  * o  atom:feed elements MUST NOT contain more than one atom:icon
  *    element.
  * o  atom:feed elements MUST NOT contain more than one atom:logo
  *    element.
  * o  atom:feed elements MUST contain exactly one atom:id element.
  * o  atom:feed elements SHOULD contain one atom:link element with a rel
  *    attribute value of "self".  This is the preferred URI for
  *    retrieving Atom Feed Documents representing this Atom feed.
  * o  atom:feed elements MUST NOT contain more than one atom:link
  *    element with a rel attribute value of "alternate" that has the
  *    same combination of type and hreflang attribute values.
  * o  atom:feed elements MAY contain additional atom:link elements
  *    beyond those described above.
  * o  atom:feed elements MUST NOT contain more than one atom:rights
  *    element.
  * o  atom:feed elements MUST NOT contain more than one atom:subtitle
  *    element.
  * o  atom:feed elements MUST contain exactly one atom:title element.
  * o  atom:feed elements MUST contain exactly one atom:updated element.
  *
  * If multiple atom:entry elements with the same atom:id value appear in
  * an Atom Feed Document, they represent the same entry.  Their
  * atom:updated timestamps SHOULD be different.  If an Atom Feed
  * Document contains multiple entries with the same atom:id, Atom
  * Processors MAY choose to display all of them or some subset of them.
  * One typical behavior would be to display only the entry with the
  * latest atom:updated timestamp.
*)

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

let make_feed (l : [< feed'] list) =
  (** atomAuthor* *)
  let authors = List.fold_left
      (fun acc -> function `Author x -> x :: acc | _ -> acc) [] l in
  (** atomCategory* *)
  let categories = List.fold_left
      (fun acc -> function `Category x -> x :: acc | _ -> acc) [] l in
  (** atomContributor* *)
  let contributors = List.fold_left
      (fun acc -> function `Contributor x -> x :: acc | _ -> acc) [] l in
  (** atomLink* *)
  let links = List.fold_left
      (fun acc -> function `Link x -> x :: acc | _ -> acc) [] l in
  (** atomGenerator? *)
  let generator = match find (function `Generator _ -> true | _ -> false) l with
    | Some (`Generator g) -> Some g
    | _ -> None
  in
  (** atomIcon? *)
  let icon = match find (function `Icon _ -> true | _ -> false) l with
    | Some (`Icon i) -> Some i
    | _ -> None
  in
  (** atomId *)
  let id = match find (function `ID _ -> true | _ -> false) l with
    | Some (`ID i) -> i
    | _ -> Error.raise_expectation (Error.Tag "id") (Error.Tag "feed")
  in
  (** atomLogo? *)
  let logo = match find (function `Logo _ -> true | _ -> false) l with
    | Some (`Logo l) -> Some l
    | _ -> None
  in
  (** atomRights? *)
  let rights = match find (function `Rights _ -> true | _ -> false) l with
    | Some (`Rights r) -> Some r
    | _ -> None
  in
  (** atomSubtitle? *)
  let subtitle = match find (function `Subtitle _ -> true | _ -> false) l with
    | Some (`Subtitle s) -> Some s
    | _ -> None
  in
  (** atomTitle *)
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ -> Error.raise_expectation (Error.Tag "title") (Error.Tag "feed")
  in
  (** atomUpdated *)
  let updated = match find (function `Updated _ -> true | _ -> false) l with
    | Some (`Updated u) -> u
    | _ -> Error.raise_expectation (Error.Tag "updated") (Error.Tag "feed")
  in
  (** atomEntry* *)
  let entries = List.fold_left
      (fun acc -> function `Entry x -> x :: acc | _ -> acc) [] l in
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
    ("entry", (fun ctx a -> `Entry (entry_of_xml ctx a)));
  ] in
  generate_catcher ~data_producer make_feed

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
  generate_catcher ~data_producer (fun x -> x)

let analyze input =
  let el tag datas = Node (tag, datas) in
  let data data = Leaf data in
  let (_, tree) = Xmlm.input_doc_tree ~el ~data input in
  let aux = function
    | Node (tag, datas) when tag_is tag "feed" -> feed_of_xml (tag, datas)
    | _ -> Error.raise_expectation (Error.Tag "feed") Error.Root
  in aux tree
