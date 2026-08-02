# Wardrobe Studio

Wardrobe Studio models a personal wardrobe as durable clothing records that can be collected, reviewed, and later used to create Looks.

## Language

**Wardrobe Item**:
A durable record of one piece of clothing or wearable accessory in a person's wardrobe, whether wanted or owned.
_Avoid_: Object, garment record

**Item Metadata**:
The editable short name, strict category, colors, and optional notes describing a Wardrobe Item. GPT proposes the name, category, and colors; the person remains authoritative.
_Avoid_: Detection response, AI tags

**Source Photo**:
An uploaded photo from which one or more Wardrobe Items can be identified. It remains private and durable provenance visible from each derived item's detail page.
_Avoid_: Item image, shelf image

**Shelf Image**:
A clean, isolated display image of a Wardrobe Item, generated from its appearance in a Source Photo for browsing the wardrobe.
_Avoid_: Cutout, extraction, object raster

**Shelf Image Version**:
An immutable generated candidate for a Wardrobe Item's Shelf Image. A person must Keep a version before it becomes the item's current image; older kept versions remain restorable.
_Avoid_: Retry, overwritten image

**Item State**:
The reversible placement of a Wardrobe Item in Wanting, Owning, or Archive. Purchasing an item changes its state without changing its identity or history.
_Avoid_: Collection, tab

**Look**:
A saved outfit image that combines a fitting profile with selected Wardrobe Items. Looks follow the first usable wardrobe release.
_Avoid_: Shelf image, generation result
