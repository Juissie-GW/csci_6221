# Embedding.jl

module Embedding

using Transformers
using Transformers.TextEncoders
using Transformers.HuggingFace

export Embedder, embed


"""A struct for holding a model and a tokenizer

Attributes
----------
tokenizer : an tokenizer object, e.g. BertTextEncoder
    maps your string to tokens the model can understand
model : a model object, e.g. HGFBertModel
    the actual model architecture and weights to perform inference with

Notes
-----
You can get class-like behavior in Julia by defining a struct and
functions that operate on that struct.
"""
struct Embedder
    tokenizer
    model
end


"""Function to initialize an Embedder struct from a HuggingFace
model path.

Parameters
----------
model_name : String
    a path to a HuggingFace-hosted model
    e.g. "BAAI/bge-small-en-v1.5"

Notes
-----
This is sort of like a constructor in Python.
"""
function Embedder(model_name::String)
    tokenizer, model = load_hgf_pretrained(model_name)
    return Embedder(tokenizer, model)
end


"""Embeds a textual sequence using a provided model

Parameters
----------
embedder : Embedder
    an initialized Embedder struct
text : String
    the text sequence you want to embed

Notes
-----
This is sort of like a class method for the Embedder

Julia has something called multiple dispatch that can be used to 
make this cleaner, but I'm going to handle that at a later times
"""
function embed(embedder::Embedder, text::String)
    if embedder.model isa Transformers.HuggingFace.HGFBertModel
        # if the model is a bert model, direct to bert-specific Function
        embedding = embed_from_bert(embedder, text)
    else
        error("Not-Bert models are not yet supported.")
    end
    return embedding
end


"""Embeds a textual sequence using a provided Bert model

Parameters
----------
embedder : Embedder
    an initialized Embedder struct
    the associated model and tokenizer should be Bert-specific
text : String
    the text sequence you want to embed
"""
function embed_from_bert(embedder::Embedder, text::String)
    encoded_input = encode(embedder.tokenizer, text)
    model_output = embedder.model(encoded_input)
    cls_embedding = model_output.hidden_state[:, 1, :]
    return cls_embedding
end

end # this ends the module