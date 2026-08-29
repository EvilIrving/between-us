#!/usr/bin/env python3
"""Dear Us first visual version: 180 runtime entries + 3 lock stills.

This module is the source of truth. generate_assets.py composes prompts
from the visual bible plus each entry's focus. Do not hand-edit the
dumped JSON except via this file.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BIBLE_PATH = ROOT / "DesignAssets" / "visual_bible.md"
MANIFEST_PATH = ROOT / "DesignAssets" / "asset_manifest.json"

MODEL = "gpt-image-2"
CANVAS_ROOM = "1024x1536"
CANVAS_OBJECT = "1024x1024"
ANCHOR_DESK = {"x": 0.50, "y": 0.82}
ANCHOR_CENTER = {"x": 0.50, "y": 0.50}

PALETTE = {
    "wall": "#F6F2E9",
    "desk": "#C4A882",
    "ink": "#2F2D2B",
    "star": "#E69E42",
    "capsule": "#789B8A",
    "paper": "#8C827D",
}

NEGATIVE = (
    "No text, letters, numbers, UI, watermarks, logos, captions, or contact-sheet labels. "
    "No people unless the asset explicitly asks for a hand. No phones. "
    "No office trash can, pedal bin, garbage bag, recycling mark. "
    "No milk-plastic glass, sea-glass sludge, neon, chrome, marble luxury kitchen, "
    "cartoon outlines, cheap CGI product render, or a bottle filling the whole frame."
)

BIBLE_SUMMARY = """
Dear Us locked still-life system.
Quiet shared apartment, cream plaster wall {wall}, warmer oak desk, tungsten + window light from upper left.
Camera locked: 50mm equivalent, 12-15 degrees down. Objects are small desk things, never full-bleed.
Star jar: clear glass with visible thickness and gentle wall refraction, cork-and-thin-wood lid with stopper. Closed lid rim fully covers the mouth. Opening is an arc, not a straight lift; neck height never shortens; stopper travels with the lid.
Capsule box: small sage enamel travel case, rounded, tiny brass hinge. Closed seam is a single tight line.
Paper basket: small warm-gray ceramic or fine rattan receiving basket, desk scale, meaning "safely catch", never discard.
Stars: handmade amber origami. Capsules: sage + cream matte two-tone. Paper balls: warm-gray crumpled handwritten paper with visible layers.
Same camera, light, scale, and table height across all object shots.
""".format(**PALETTE)


def _entry(
    *,
    id: str,
    group: str,
    stage: str,
    screen: str,
    object: str,
    semantic: str,
    state: str,
    prompt_focus: str,
    canvas: str = CANVAS_OBJECT,
    alpha: bool = True,
    frame: int | None = None,
    anchor: dict[str, float] | None = None,
    appearance: list[str] | None = None,
    reduce_motion_alt: str | None = None,
    reference: list[str] | None = None,
    depends_on: list[str] | None = None,
    reuse: str | None = None,
    mode: str | None = None,
    export_sizes: list[int] | None = None,
    runtime: bool = True,
) -> dict[str, Any]:
    if mode is None:
        mode = "copy" if reuse else ("edit" if reference else "generate")
    item: dict[str, Any] = {
        "id": id,
        "group": group,
        "stage": stage,
        "runtime": runtime,
        "screen": screen,
        "object": object,
        "semantic": semantic,
        "state": state,
        "frame": frame,
        "anchor": anchor or (ANCHOR_CENTER if group == "logos" else ANCHOR_DESK),
        "canvas": canvas,
        "alpha": alpha,
        "appearance": appearance or ["light"],
        "reduce_motion_alt": reduce_motion_alt,
        "reference": reference or [],
        "depends_on": depends_on or list(reference or ([] if not reuse else [reuse])),
        "reuse": reuse,
        "mode": mode,
        "export_sizes_pt": export_sizes or [],
        "prompt_focus": prompt_focus.strip(),
    }
    return item


def lock_stills() -> list[dict[str, Any]]:
    return [
        _entry(
            id="lock_star_form",
            group="lock",
            stage="lock",
            runtime=False,
            screen="lock",
            object="star_jar",
            semantic="canonical closed geometry",
            state="closed",
            alpha=False,
            reference=["env_room_master"],
            prompt_focus="""
Isolate the star jar from the locked master scene. Same glass, cork-wood lid, stopper, star contents, camera angle, and lighting.
Single object, closed, lid rim covering the mouth completely. Sit it on a short slice of the same oak desk. Keep the cream wall as a simple backdrop.
Do not redesign the jar. Do not straighten the lid into a stock photo bottle.
""",
        ),
        _entry(
            id="lock_capsule_form",
            group="lock",
            stage="lock",
            runtime=False,
            screen="lock",
            object="capsule_box",
            semantic="canonical closed geometry",
            state="closed",
            alpha=False,
            reference=["env_room_master"],
            prompt_focus="""
Isolate the sage enamel capsule box from the locked master scene. Same rounded travel-case scale, brass hinge, tight closed seam, camera and light.
Single object on a short slice of the same oak desk, cream wall behind. Closed. No capsules spilled outside.
Do not turn it into a pharmacy blister pack or a huge medicine chest.
""",
        ),
        _entry(
            id="lock_paper_form",
            group="lock",
            stage="lock",
            runtime=False,
            screen="lock",
            object="paper_basket",
            semantic="canonical receiving geometry",
            state="closed",
            alpha=False,
            reference=["env_room_master"],
            prompt_focus="""
Isolate the paper receiving basket from the locked master scene. Same warm-gray ceramic or fine rattan desk basket, same crumpled paper balls inside, same camera and light.
Single object on a short oak desk slice, cream wall behind. It must feel like catching, not discarding.
No office trash can, no lid pedal, no garbage bag, no recycling symbol.
""",
        ),
    ]


def environment() -> list[dict[str, Any]]:
    room = dict(canvas=CANVAS_ROOM, alpha=False, anchor=ANCHOR_CENTER, screen="home")
    return [
        _entry(
            id="env_room_master",
            group="environment",
            stage="lock",
            object="room",
            semantic="locked master scene with three containers",
            state="dusk",
            prompt_focus="""
Complete master scene, iPhone portrait crop.
Cream plaster wall fills the upper half. Warm oak desk in the lower third. Soft window light from upper left, warm lamp fill, short soft shadows.
On the desk, three physical objects:
- Center back, slightly larger: small clear glass jar, cork-and-wood lid closed so the rim fully covers the mouth, a handful of handmade amber origami stars inside. Desk-object scale, never filling the frame.
- Front left, smaller: sage enamel rounded capsule box, tiny brass hinge, closed tight.
- Front right, smaller: warm-gray ceramic/rattan receiving basket with two handmade paper balls.
Generous empty wall above. Quiet, tactile, still-life photograph with slight material honesty. Not CGI, not cartoon, not luxury ad.
""",
            **room,
        ),
        _entry(
            id="env_room_empty",
            group="environment",
            stage="production",
            object="room",
            semantic="empty compositing plate",
            state="empty",
            reference=["env_room_master"],
            prompt_focus="Same locked room, same camera and lighting, but remove all three containers. Bare oak desk and cream wall only. Keep window light and warm lamp. No new furniture.",
            **room,
        ),
        _entry(
            id="env_room_wall",
            group="environment",
            stage="production",
            object="wall",
            semantic="wall plate",
            state="idle",
            reference=["env_room_master"],
            prompt_focus="Crop/rebuild only the cream plaster wall and window from the master. No desk, no objects. Soft daylight gradient, no decoration.",
            **room,
        ),
        _entry(
            id="env_room_desk",
            group="environment",
            stage="production",
            object="desk",
            semantic="desk plate",
            state="idle",
            reference=["env_room_master"],
            prompt_focus="Only the oak desk surface from the master, same wood grain and light. No objects. Transparent or clean edges above the desk line if possible; otherwise cream wall meeting the desk exactly as in the master.",
            **room,
        ),
        _entry(
            id="env_room_window_light",
            group="environment",
            stage="production",
            object="light",
            semantic="window gobo",
            state="window",
            canvas=CANVAS_OBJECT,
            alpha=True,
            reference=["env_room_master"],
            prompt_focus="A transparent lighting layer: soft window-shaped light falloff from upper left, faint curtain-like gradient. No furniture. Black/transparent where there is no light. Not a photograph of a window frame unless extremely soft.",
        ),
        _entry(
            id="env_room_lamp_warm",
            group="environment",
            stage="production",
            object="light",
            semantic="warm key fill",
            state="lamp",
            canvas=CANVAS_OBJECT,
            alpha=True,
            reference=["env_room_master"],
            prompt_focus="Transparent warm tungsten fill glow, low intensity, from the same side as the master lamp. No visible lamp object. No orange neon.",
        ),
        _entry(
            id="env_room_shadow_ground",
            group="environment",
            stage="production",
            object="shadow",
            semantic="ground contact shadow field",
            state="idle",
            canvas=CANVAS_OBJECT,
            alpha=True,
            reference=["env_room_master"],
            prompt_focus="Transparent layer of short soft contact shadows on a desk plane, empty of objects. Use this as a reusable shadow field. No hard black blobs.",
        ),
        _entry(
            id="env_star_scene",
            group="environment",
            stage="production",
            object="room",
            semantic="star jar detail scene",
            state="star",
            screen="star_detail",
            reference=["env_room_master", "lock_star_form"],
            prompt_focus="Same room language as the master, camera a little closer, star jar as the only object on the desk, matching lock_star_form geometry. Empty wall above. No other containers.",
            **room,
        ),
        _entry(
            id="env_capsule_scene",
            group="environment",
            stage="production",
            object="room",
            semantic="capsule box detail scene",
            state="capsule",
            screen="capsule_detail",
            reference=["env_room_master", "lock_capsule_form"],
            prompt_focus="Same room language, closer camera, only the sage capsule box on the desk, matching lock_capsule_form. No other containers.",
            **room,
        ),
        _entry(
            id="env_paper_scene",
            group="environment",
            stage="production",
            object="room",
            semantic="paper basket detail scene",
            state="paper",
            screen="paper_detail",
            reference=["env_room_master", "lock_paper_form"],
            prompt_focus="Same room language, closer camera, only the receiving basket on the desk, matching lock_paper_form. No office bin.",
            **room,
        ),
        _entry(
            id="env_compose_paper",
            group="environment",
            stage="production",
            object="paper_surface",
            semantic="writing surface",
            state="compose",
            screen="compose",
            canvas=CANVAS_OBJECT,
            alpha=False,
            reference=["env_room_master"],
            prompt_focus="A blank handmade cream writing paper filling most of the frame, lying on the oak desk, same light as the master. Empty, no handwriting. Paper is the object, not a UI card.",
        ),
        _entry(
            id="env_reveal_table",
            group="environment",
            stage="production",
            object="desk",
            semantic="reveal table",
            state="reveal",
            screen="reveal",
            reference=["env_room_master"],
            prompt_focus="Closer crop of the oak desk from the master, empty, ready to hold an unfolded note. Cream wall above. No containers.",
            **room,
        ),
        _entry(
            id="env_room_morning",
            group="environment",
            stage="production",
            object="room",
            semantic="morning light variant of the locked room",
            state="morning",
            reference=["env_room_master"],
            prompt_focus="The locked master scene with cooler, earlier window light. Same furniture, same three containers, same camera. Do not restyle objects. Only the light changes.",
            **room,
        ),
        _entry(
            id="env_room_night",
            group="environment",
            stage="production",
            object="room",
            semantic="night plate, not a restyle",
            state="night",
            appearance=["dark"],
            reference=["env_room_master"],
            prompt_focus="The locked master scene at night: wall darker, warm lamp becomes the key, window is dim. Same three containers and camera. Still readable, not a black void, not neon.",
            **room,
        ),
    ]


def _container_layers(kind: str, lock_id: str, noun: str, extra: str) -> list[dict[str, Any]]:
    refs = ["env_room_master", lock_id]
    parts = [
        ("body", "body only", f"Only the {noun} body, no lid if it has a separate lid. Match {lock_id} exactly. Transparent background. {extra}"),
        ("lid" if kind != "paper" else "rim", "lid" if kind != "paper" else "rim", (
            f"Isolated lid of the {noun} including the stopper or inner face that travels with the lid. Match {lock_id}. Transparent background."
            if kind != "paper"
            else f"Isolated receiving rim of the {noun}, slightly flared, matching {lock_id}. Transparent background."
        )),
        ("mouth", "mouth", f"Close, isolated mouth/opening of the {noun} at the locked scale. Neck or rim height complete. Transparent background. {extra}"),
        ("cavity", "cavity", f"Interior cavity of the {noun} as a layer: empty volume, readable bottom, transparent outside. Match {lock_id}."),
        ("occlusion_front", "front occlusion", f"Front plane of the {noun} used to occlude contents. Glass/ceramic/enamel matching {lock_id}. Transparent outside the front wall."),
        ("shadow", "contact shadow", f"Only the contact shadow of the {noun} on transparency. No desk drawing, no object body."),
        ("highlight", "specular highlight", f"Only the real lighting highlight of the {noun} on transparency. No fake white stripe sticker."),
        ("closed", "closed assembled", f"Assembled closed {noun}, matching {lock_id} one-to-one. Transparent background, no desk. Lid/rim must cover the opening."),
        ("open", "open rest", f"Assembled open rest pose of the {noun}. For the jar: lid arced to the side, stopper on the lid, neck full height. For the box: lid hinged ~80 degrees. For the basket: receiving mouth unobstructed. Transparent background. Match {lock_id} geometry."),
        ("empty", "empty", f"Assembled {noun} with no contents. Same geometry as the locked form. Transparent background."),
    ]
    items = []
    for state, semantic, focus in parts:
        items.append(
            _entry(
                id=f"container_{kind}_{state}",
                group="containers",
                stage="production",
                screen=f"{kind}_detail",
                object=f"{kind}_container",
                semantic=semantic,
                state=state,
                reference=refs,
                prompt_focus=focus,
            )
        )
    return items


def containers() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    items += _container_layers(
        "star",
        "lock_star_form",
        "star jar",
        "Closed lid rim covers the mouth. Stopper is part of the lid. Neck never shortens.",
    )
    items += _container_layers(
        "capsule",
        "lock_capsule_form",
        "capsule box",
        "Sage enamel, tiny brass hinge, travel-case scale.",
    )
    items += _container_layers(
        "paper",
        "lock_paper_form",
        "paper basket",
        "Receiving basket, not a trash can.",
    )
    return items


def _content_set(kind: str, noun: str, lock_id: str, focuses: dict[str, str]) -> list[dict[str, Any]]:
    items = []
    for state, focus in focuses.items():
        items.append(
            _entry(
                id=f"content_{kind}_{state}",
                group="contents",
                stage="production",
                screen="compose" if "blank" in state or "held" in state else f"{kind}_detail",
                object=f"{kind}_content",
                semantic=state.replace("_", " "),
                state=state,
                reference=["env_room_master", lock_id],
                prompt_focus=focus,
            )
        )
    return items


def contents() -> list[dict[str, Any]]:
    star = {
        "idle": "A single handmade amber origami lucky star, irregular folds, tactile paper. Transparent background. Not a metal badge.",
        "new": "The same origami star with a slightly stronger warm inner glow, still paper. Transparent background.",
        "opened": "The same star after being opened once: a bit looser, one flap less tight. Transparent background.",
        "blank": "An unwritten pale cream origami star, empty of marks. Transparent background.",
        "folded_tight": "Tightly folded amber origami star, compact silhouette. Transparent background.",
        "folded_loose": "Loosely folded amber origami star, puffier. Transparent background.",
        "cluster_few": "Three or four handmade amber origami stars in a small pile, not overlapping into a mess. Transparent background.",
        "cluster_many": "About ten handmade amber origami stars as a loose handful, still countable. Transparent background.",
        "in_jar_bottom": "A few amber origami stars as they would rest at the bottom of the locked jar, viewed through no glass (contents only). Transparent background.",
        "held": "One amber origami star as if just picked up, slightly larger in frame, still no hand unless a faint fingertip-scale shadow. Transparent background.",
        "shadow": "Contact shadow only of a small origami star, transparent otherwise.",
        "highlight": "Paper highlight only of an origami star, transparent otherwise. No plastic shine.",
    }
    capsule = {
        "idle": "One matte two-tone capsule, sage and cream halves, travel-case scale. Transparent background. Not a transparent drugstore pill.",
        "new": "The same capsule with a slightly fresher sage half. Transparent background.",
        "opened": "The same capsule after being split once, still closed but with a visible hairline seam. Transparent background.",
        "blank": "An empty unsealed cream/sage capsule, slightly open gap. Transparent background.",
        "folded_tight": "Capsule fully sealed, tight equatorial join. Transparent background.",
        "folded_loose": "Capsule sealed but the two halves slightly mismatched, handmade. Transparent background.",
        "cluster_few": "Four capsules resting as in the locked box, sage+cream. Transparent background.",
        "cluster_many": "About ten capsules in a shallow handful, still the same design. Transparent background.",
        "in_jar_bottom": "Capsules as they would lie in the locked box cavity, no box drawn. Transparent background.",
        "held": "One capsule isolated, ready to be placed. Transparent background.",
        "shadow": "Contact shadow only of one capsule. Transparent otherwise.",
        "highlight": "Soft enamel/matte highlight of one capsule. Transparent otherwise.",
    }
    paper = {
        "idle": "One warm-gray handmade paper ball, visible crumpled layers, not a white sphere. Transparent background.",
        "new": "The same paper ball a bit tighter, freshly crumpled. Transparent background.",
        "opened": "Paper ball after one attempt to open: looser, one corner peeking. Transparent background.",
        "blank": "A blank cream note already crumpled once, no writing. Transparent background.",
        "folded_tight": "Tight dense paper ball. Transparent background.",
        "folded_loose": "Loose paper ball, more facets. Transparent background.",
        "cluster_few": "Two or three paper balls as in the locked basket. Transparent background.",
        "cluster_many": "About eight paper balls, still handmade notes, not trash. Transparent background.",
        "in_jar_bottom": "Paper balls as they rest in the basket cavity, no basket drawn. Transparent background.",
        "held": "One paper ball isolated, about to be placed. Transparent background.",
        "shadow": "Contact shadow only of a paper ball. Transparent otherwise.",
        "highlight": "Dry paper highlight only. Transparent otherwise.",
    }
    items = []
    items += _content_set("star", "star", "lock_star_form", star)
    items += _content_set("capsule", "capsule", "lock_capsule_form", capsule)
    items += _content_set("paper", "paper", "lock_paper_form", paper)
    return items


def logos() -> list[dict[str, Any]]:
    family = (
        "Flat mark on transparent background, dark ink #2F2D2B. 24-unit grid, stroke 1.75, round caps and joins. "
        "Same negative-space language as the rest of the logo family. Not a color swap of another mark. "
        "No gradients, no photoreal, no SF Symbol, no drop shadow. Centered, readable at 16pt silhouette."
    )
    specs = [
        ("logo_app", "app", "two people keeping one thing", "idle",
         "Two overlapping vessel silhouettes sharing one inner cavity. The shared negative space is the kept thing. App mark, not a letterform. Also must work as a 1024 app icon later on cream paper, but this file is the transparent mark."),
        ("logo_star", "star", "collect", "idle",
         "A bottle-mouth negative space containing one five-point star. Collection, not sparkle."),
        ("logo_star_active", "star", "collect active", "active",
         "The star-bottle mark with a slightly bolder inner star, same geometry as logo_star. Not just a color change."),
        ("logo_star_waiting", "star", "collect waiting", "waiting",
         "The star-bottle mark with a small unfilled star, same outer geometry. Waiting to be opened."),
        ("logo_capsule", "capsule", "seal and pass", "idle",
         "A capsule split by a vertical seal line, like closing a letter. Pass/seal, not pharmacy."),
        ("logo_capsule_active", "capsule", "seal active", "active",
         "Capsule mark with a confirmed seal bar, same geometry as logo_capsule."),
        ("logo_capsule_waiting", "capsule", "seal waiting", "waiting",
         "Capsule mark with an open hairline gap in the seal, same outer geometry."),
        ("logo_paper", "paper", "safely catch", "idle",
         "Two arcs forming a basket mouth catching a tiny folded note. Catch, not trash."),
        ("logo_paper_active", "paper", "catch active", "active",
         "Basket-mouth mark with the note seated in the cavity, same geometry as logo_paper."),
        ("logo_paper_waiting", "paper", "catch waiting", "waiting",
         "Basket-mouth mark empty, note absent, same outer arcs."),
        ("logo_action_fold", "action", "fold", "fold", "A strip of paper becoming a chevron fold. Action: fold a star."),
        ("logo_action_seal", "action", "seal", "seal", "A capsule and a short seal bar meeting. Action: seal."),
        ("logo_action_crumple", "action", "crumple", "crumple", "A paper sheet tightening into a spiral crumple. Action: crumple."),
        ("logo_action_open", "action", "open", "open", "A lid leaving a mouth along a short arc. Action: open. Not a play-triangle."),
        ("logo_action_deposit", "action", "put in", "deposit", "A small object entering a mouth from below. Action: put in."),
        ("logo_action_respond", "action", "respond", "respond", "Two small marks exchanging, not a chat bubble. Action: leave something in return."),
        ("logo_action_hold", "action", "hold", "hold", "A compact progress-arc around a small object. Action: hold. Not a giant palm."),
        ("logo_action_cancel", "action", "cancel", "cancel", "A small object returning to rest along a short reverse path. Cancel, not a heavy X brand."),
        ("logo_action_retry", "action", "retry", "retry", "A short returning hook, same stroke family. Retry."),
        ("logo_action_leave", "action", "leave one", "leave", "A blank object beside a mouth. Leave one thing."),
        ("logo_action_close", "action", "close", "close", "A lid reseating on a mouth. Close/put away."),
        ("logo_action_write", "action", "write", "write", "A short pen stroke on a tiny paper, same grid. Write."),
        ("logo_status_waiting", "status", "waiting", "waiting", "A small unopened object mark. Status: waiting."),
        ("logo_status_opened", "status", "opened", "opened", "The same object with one flap/lid settled open. Status: opened."),
        ("logo_status_draft", "status", "draft", "draft", "A half-formed object, still held. Status: draft kept."),
        ("logo_status_syncing", "status", "syncing", "syncing", "Two small ticks offset, not a spinner toy. Status: syncing."),
        ("logo_status_offline", "status", "offline", "offline", "A quiet gap in a connecting stroke. Status: waiting for network."),
        ("logo_status_error", "status", "error", "error", "A restrained break in the stroke, not a red siren. Status: error."),
        ("logo_status_empty", "status", "empty", "empty", "The container outline with an empty cavity. Status: empty."),
        ("logo_status_recording", "status", "recording", "recording", "A small solid dot inside the same grid, not a glowing orb. Status: recording."),
    ]
    items = []
    for id_, object_, semantic, state, focus in specs:
        sizes = [16, 24, 48]
        if id_ == "logo_app":
            sizes.append(1024)
        items.append(
            _entry(
                id=id_,
                group="logos",
                stage="production",
                screen="chrome",
                object=object_,
                semantic=semantic,
                state=state,
                anchor=ANCHOR_CENTER,
                export_sizes=sizes,
                prompt_focus=f"{family}\n{focus}",
            )
        )
    return items


def _motion_frames(
    kind: str,
    lock_id: str,
    action: str,
    frames: list[tuple[str, str]],
    reduce_to: str,
) -> list[dict[str, Any]]:
    items = []
    for index, (state_note, focus) in enumerate(frames, start=1):
        frame_id = f"container_{kind}_{action}_f{index:02d}"
        items.append(
            _entry(
                id=frame_id,
                group="motion",
                stage="production",
                screen=f"{kind}_{action}",
                object=f"{kind}_container",
                semantic=f"{action} key pose",
                state=state_note,
                frame=index,
                reduce_motion_alt=reduce_to if index != 5 else None,
                reference=["env_room_master", lock_id],
                prompt_focus=focus,
            )
        )
    return items


def motion() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []

    items += _motion_frames(
        "star",
        "lock_star_form",
        "open",
        [
            ("closed", "Star jar fully closed, matching lock_star_form. Transparent background. Sequence in-point."),
            ("lid_clears_mouth", "Same jar: lid has just left the mouth. Mouth fully visible, stopper still under the lid, neck not shortened. Slight arc, not a straight lift. Transparent background."),
            ("arc_mid", "Lid traveling on a wrist-like arc to the side, tilted around the knob, stopper visible, neck full height. This pose cannot be a simple rotate of the closed lid. Transparent background."),
            ("lid_aside", "Lid almost at rest beside the jar, more tilt, mouth clear, occlusion of the neck resolved. Transparent background."),
            ("open_rest", "Open rest pose: lid at the side, quiet. Same as the intended open still. Transparent background."),
            ("open_static_alt", "Reduce-motion static: jar open, lid already at the side, no in-between. Transparent background."),
        ],
        "container_star_open_f06",
    )
    items += _motion_frames(
        "star",
        "lock_star_form",
        "deposit",
        [
            ("approach", "Open jar matching the locked geometry; one origami star below the mouth, not yet entering. Transparent background."),
            ("threshold", "Star crossing the mouth plane; glass rim occludes part of the star. This occlusion cannot be a simple scale. Transparent background."),
            ("entering", "Star inside the neck, bent by the mouth silhouette, front glass beginning to cover it. Transparent background."),
            ("falling", "Star in the cavity, partly behind front glass, above the existing stars. Transparent background."),
            ("settled", "Star settled among the others at the bottom. Lid still open. Transparent background."),
            ("reseated", "Jar closed again after deposit; new star readable inside. Transparent background."),
        ],
        "container_star_deposit_f05",
    )
    items += _motion_frames(
        "star",
        "lock_star_form",
        "reveal",
        [
            ("folded", "A closed handmade origami star, large in frame, transparent background. Reveal in-point."),
            ("first_flap", "First paper flap releasing; silhouette changes. Transparent background."),
            ("opening", "Star unfolding into a bent paper form that is no longer a star silhouette. Transparent background."),
            ("spreading", "Paper spreading, still with origami memory folds. Transparent background."),
            ("almost_flat", "Almost flat cream/amber note with remaining fold ridges. Transparent background."),
            ("flat_note", "Fully opened note, blank, handmade paper. Reduce-motion may jump here. Transparent background."),
        ],
        "container_star_reveal_f06",
    )

    items += _motion_frames(
        "capsule",
        "lock_capsule_form",
        "open",
        [
            ("closed", "Closed sage capsule box matching lock_capsule_form. Transparent background."),
            ("seal_breaks", "Lid just cracking at the hinge, inner lip becoming visible, front wall still covering contents. Transparent background."),
            ("hinge_mid", "Lid at about 45 degrees. Interior cavity readable, hinge present. Cannot be a simple 2D rotate of a flat lid photo. Transparent background."),
            ("lid_high", "Lid near 80 degrees, capsules or empty slots visible, front wall occlusion changing. Transparent background."),
            ("open_rest", "Box open at rest, lid up. Transparent background."),
            ("open_static_alt", "Reduce-motion static open box. Transparent background."),
        ],
        "container_capsule_open_f06",
    )
    items += _motion_frames(
        "capsule",
        "lock_capsule_form",
        "deposit",
        [
            ("approach", "Open box; one capsule below the mouth. Transparent background."),
            ("threshold", "Capsule crossing the box lip; lip occludes part of it. Transparent background."),
            ("entering", "Capsule dropping into a slot, half hidden by the front wall. Transparent background."),
            ("seating", "Capsule lying in the cavity. Transparent background."),
            ("settled", "Capsule settled with others, lid still open. Transparent background."),
            ("reseated", "Box closed after deposit. Transparent background."),
        ],
        "container_capsule_deposit_f05",
    )
    items += _motion_frames(
        "capsule",
        "lock_capsule_form",
        "reveal",
        [
            ("whole", "One closed sage-cream capsule, large. Transparent background."),
            ("hairline", "Hairline split at the equator. Transparent background."),
            ("crack", "Two halves beginning to separate, inner paper edge visible. Transparent background."),
            ("open_halves", "Halves apart, a small folded note starting to come out. Transparent background."),
            ("note_out", "Note mostly out, capsule halves resting. Transparent background."),
            ("note_flat", "Note opened beside the empty halves. Transparent background."),
        ],
        "container_capsule_reveal_f06",
    )

    items += _motion_frames(
        "paper",
        "lock_paper_form",
        "open",
        [
            ("rest", "Receiving basket at rest matching lock_paper_form, paper balls inside, front wall occluding them. Transparent background."),
            ("tilt", "Basket slightly presenting its mouth; occlusion of contents changes. Not an office bin tipping trash. Transparent background."),
            ("mouth_clear", "Mouth more open to the camera, interior readable, front occlusion reduced. Transparent background."),
            ("ready", "Basket in receiving pose, empty-enough cavity visible. Transparent background."),
            ("open_rest", "Stable receiving rest pose. Transparent background."),
            ("open_static_alt", "Reduce-motion static receiving pose. Transparent background."),
        ],
        "container_paper_open_f06",
    )
    items += _motion_frames(
        "paper",
        "lock_paper_form",
        "deposit",
        [
            ("approach", "Basket mouth; one paper ball above, not yet in. Transparent background."),
            ("threshold", "Paper ball crossing the rim; rim occludes it. Transparent background."),
            ("entering", "Paper ball inside, half behind the front wall. Transparent background."),
            ("nesting", "Paper ball nesting among others. Transparent background."),
            ("settled", "Settled in the basket. Transparent background."),
            ("rest_closed", "Basket back at rest after catching. Transparent background."),
        ],
        "container_paper_deposit_f05",
    )
    items += _motion_frames(
        "paper",
        "lock_paper_form",
        "reveal",
        [
            ("ball", "One tight handmade paper ball, large. Transparent background."),
            ("corner", "One corner peeling; silhouette breaks. Transparent background."),
            ("unfurling", "Crumple unfurling, still 3D, not a flat scale-up. Transparent background."),
            ("crumpled_sheet", "Sheet mostly open but heavily wrinkled. Transparent background."),
            ("smoothing", "Sheet almost readable as a note, ridges remaining. Transparent background."),
            ("flat_note", "Opened note, handmade paper, blank. Transparent background."),
        ],
        "container_paper_reveal_f06",
    )
    return items


def feedback() -> list[dict[str, Any]]:
    specs = [
        ("ui_onboard_create_space", "onboarding", "create space", "An empty star jar on the locked desk, inviting to hold, no UI chrome, no slogan. Portrait still."),
        ("ui_onboard_local_preview", "onboarding", "local preview", "The locked room with the three containers, slightly quieter light, no network cues, no eye icon."),
        ("ui_onboard_open_invite", "onboarding", "open invite", "The locked room with a small cream envelope-like paper on the desk, not a system share sheet screenshot."),
        ("ui_empty_drawer", "drawer", "empty", "An empty shallow wooden drawer interior, cream notes absent. Quiet, no icons."),
        ("ui_empty_star", "star_detail", "empty", "Locked star jar empty and closed, same geometry. Transparent object on implied desk light."),
        ("ui_empty_capsule", "capsule_detail", "empty", "Locked capsule box empty and closed."),
        ("ui_empty_paper", "paper_detail", "empty", "Locked receiving basket empty."),
        ("ui_error_save_failed", "compose", "save failed", "The compose paper with a small retained draft star/capsule/ball still on it. No warning triangle cliché. Object remains."),
        ("ui_error_network", "settings", "waiting for network", "The locked room unchanged, slightly dimmer, objects still there. No red X."),
        ("ui_error_permission_mic", "compose", "mic denied", "Voice compose surface with a quiet muted recorder object, no system alert."),
        ("ui_record_idle", "compose", "record idle", "A small matte recorder bead at rest, same ink/material family, transparent background."),
        ("ui_record_active", "compose", "record active", "The same bead with a solid quiet red core, not a glowing orb."),
        ("ui_record_cancel_armed", "compose", "cancel armed", "The bead sliding toward a cancel mark in the same stroke family."),
        ("ui_sync_waiting", "settings", "sync waiting", "Tiny paired ticks not yet meeting. Transparent."),
        ("ui_sync_done", "settings", "sync done", "Tiny paired ticks seated together. Transparent."),
        ("ui_draft_retained", "compose", "draft retained", "A half-folded star or unsealed capsule resting on the writing paper. Content was kept."),
    ]
    items = []
    for id_, screen, state, focus in specs:
        opaque = id_.startswith("ui_onboard") or id_.startswith("ui_empty_drawer") or id_ in {
            "ui_error_save_failed",
            "ui_error_network",
            "ui_error_permission_mic",
            "ui_draft_retained",
        }
        items.append(
            _entry(
                id=id_,
                group="feedback",
                stage="production",
                screen=screen,
                object="feedback",
                semantic=state,
                state=state,
                canvas=CANVAS_ROOM if opaque else CANVAS_OBJECT,
                alpha=not opaque,
                reference=["env_room_master"],
                prompt_focus=focus,
            )
        )
    return items


def all_entries() -> list[dict[str, Any]]:
    items = lock_stills() + environment() + containers() + contents() + logos() + motion() + feedback()
    seen: set[str] = set()
    for item in items:
        if item["id"] in seen:
            raise ValueError(f"duplicate id {item['id']}")
        seen.add(item["id"])
    runtime = [i for i in items if i["runtime"]]
    counts = {}
    for i in runtime:
        counts[i["group"]] = counts.get(i["group"], 0) + 1
    expected = {
        "environment": 14,
        "containers": 30,
        "contents": 36,
        "logos": 30,
        "motion": 54,
        "feedback": 16,
    }
    if counts != expected:
        raise ValueError(f"runtime group counts {counts} != {expected}")
    if len(runtime) != 180:
        raise ValueError(f"runtime count {len(runtime)}")
    lock = [i for i in items if not i["runtime"]]
    if len(lock) != 3:
        raise ValueError(f"lock count {len(lock)}")
    return items


def compose_prompt(entry: dict[str, Any]) -> str:
    alpha_line = (
        "Output PNG with a true transparent background. No floor, no wall, no checkerboard, no drop-in backdrop."
        if entry["alpha"]
        else "Opaque still. Cream wall / oak desk allowed only as specified. Fill the canvas."
    )
    frame_line = f"Frame {entry['frame']:02d} in a 6-pose sequence." if entry["frame"] else "Single still, not a sheet, not a grid."
    refs = ", ".join(entry["reference"]) if entry["reference"] else "none — this is a lock generate"
    return "\n".join(
        [
            "You are making ONE Dear Us design asset. Match the locked visual system exactly.",
            BIBLE_SUMMARY.strip(),
            f"Asset id: {entry['id']}",
            f"Screen: {entry['screen']}",
            f"Object: {entry['object']}",
            f"Semantic: {entry['semantic']}",
            f"State: {entry['state']}",
            f"Canvas: {entry['canvas']}",
            f"Anchor: {entry['anchor']['x']:.2f}, {entry['anchor']['y']:.2f}",
            f"Reference images: {refs}",
            frame_line,
            alpha_line,
            "Keep geometry, materials, and camera of any reference image. Change only what the task names.",
            "Task:",
            entry["prompt_focus"],
            NEGATIVE,
        ]
    )


def manifest_document() -> dict[str, Any]:
    entries = all_entries()
    return {
        "version": "1.0.0",
        "product": "Dear Us",
        "model": MODEL,
        "budget": {
            "runtime_entries": 180,
            "lock_stills": 3,
            "note": "@2x @3x dark-mode and 16/24/48pt exports are not extra design entries",
        },
        "rate_limit": {"per_minute": 5, "concurrency": 3},
        "bible": str(BIBLE_PATH.relative_to(ROOT)),
        "groups": {
            "environment": 14,
            "containers": 30,
            "contents": 36,
            "logos": 30,
            "motion": 54,
            "feedback": 16,
        },
        "entries": entries,
    }


if __name__ == "__main__":
    import json

    doc = manifest_document()
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    runtime = [e for e in doc["entries"] if e["runtime"]]
    print(f"wrote {MANIFEST_PATH} ({len(runtime)} runtime, {len(doc['entries']) - len(runtime)} lock)")
