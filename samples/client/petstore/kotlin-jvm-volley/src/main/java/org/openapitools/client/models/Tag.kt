/**
 *
 * Please note:
 * This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
 * Do not edit this file manually.
 *
 */

@file:Suppress(
    "ArrayInDataClass",
    "EnumEntryName",
    "RemoveRedundantQualifierName",
    "UnusedImport"
)

package org.openapitools.client.models


import com.google.gson.annotations.SerializedName
import org.openapitools.client.models.room.TagRoomModel
import org.openapitools.client.infrastructure.ITransformForStorage

/**
 * A tag for a pet
 *
 * @param id 
 * @param name 
 */

data class Tag (

    @SerializedName("id")
    val id: kotlin.Long? = null,

    @SerializedName("name")
    val name: kotlin.String? = null

): ITransformForStorage<TagRoomModel> {
    companion object { }
    override fun toRoomModel(): TagRoomModel =
        TagRoomModel(roomTableId = 0,
        id = this.id,
name = this.name,
        )

}

