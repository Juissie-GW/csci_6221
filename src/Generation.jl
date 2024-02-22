# Generation.jl

module Generation

using HTTP
using JSON
using DotEnv

include("SemanticSearch/SemanticSearch.jl")
using .SemanticSearch

export OAIGenerator, generate, generate_with_corpus


const OptionalContext = Union{Vector{String}, Nothing}


"""
    struct OAIGenerator

A struct for handling natural language generation via OpenAI's
gpt-3.5-turbo completion endpoint.

Attributes
----------
url : String
    the URL of the OpenAI API endpoint
header : Vector{Pair{String, String}}
    key-value pairs representing the HTTP headers for the request
body_dict : Dict{String, Any}
    this is the JSON payload to be sent in the body of the request

Notes
-----
All natural language generation should be done via a "Generator"
object of some kind for consistency. In the future, if we 
decide to host a model locally or something, we might do that
via a HFGenerator struct.
"""
struct OAIGenerator
    url::String
    header::Vector{Pair{String, String}}
    body_dict::Dict{String,Any}
end


"""
    function OAIGenerator(auth_token::Union{String, Nothing})

Initializes an OAIGenerator struct.

Attributes
----------
auth_token :: Union{String, Nothing}
    this is your OPENAI API key. You can either pass it explicitly as a string
    or leave this argument as nothing. In the latter case, we will look in your
    environmental variables for "OAI_KEY"
"""
function OAIGenerator(auth_token::Union{String, Nothing}=nothing)
    if isnothing(auth_token)
        path_to_env = joinpath(@__DIR__, "..", ".env")
        DotEnv.config(path_to_env)
        auth_token = ENV["OAI_KEY"]
    end

    url = "https://api.openai.com/v1/chat/completions"
    header = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $auth_token"
    ]
    body_dict = Dict(
        "model" => "gpt-3.5-turbo"
    )

    return OAIGenerator(url, header, body_dict)
end

"""
    function build_full_query(query::String, context::OptionalContext=nothing)

Given a query and a list of contextual chunks, construct a full query
incorporating both.

Parameters
----------
query : String
    the main instruction or query string
context : OptionalContext, which is Union{Vector{String}, Nothing}
    optional list of chunks providing additional context for the query

Notes
-----
We use the Alpaca prompt, found here: https://github.com/tatsu-lab/stanford_alpaca
"""
function build_full_query(query::String, context::OptionalContext=nothing)
    full_query = """
    Below is an instruction that describes a task. Write a response that appropriately completes the request.
    
    ### Instruction:
    $query
    """

    if !isnothing(context)
        context_str = join(["- " * s for s in context], "\n")
        full_query = """
        Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.
        
        ### Instruction:
        $query
        
        ### Input:
        $context_str
        
        ### Response:
        """
    end

    return full_query
end

"""
    generate(generator::Union{OAIGenerator, Nothing}, query::String, context::OptionalContext=nothing, temperature::Float64=0.7)

Generate a response based on a given query and optional context using the specified OAIGenerator. This function constructs a full query, sends it to the OpenAI API, and returns the generated response.

Parameters
----------
generator : Union{OAIGenerator, Nothing}
    an initialized generator (e..g OAIGenerator)
    leaving this as a union with nothing to note that we may want to support other 
    generator types in the future (e.g. HFGenerator, etc.)
query : String
    the main instruction or query string. This is basically your question
context : OptionalContext, which is Union{Vector{String}, Nothing}
    optional list of contextual chunk strings to provide the generator additional 
    context for the query. Ultimately, these will be coming from our vector DB
temperature : Float64
    controls the stochasticity of the output generated by the model
"""
function generate(generator::Union{OAIGenerator, Nothing}, query::String, context::OptionalContext=nothing, temperature::Float64=0.7)
    # build full query from query and context
    full_query = build_full_query(query, context)
    
    if isa(generator, OAIGenerator)
        generator.body_dict["temperature"] = temperature
        generator.body_dict["messages"] = [
            Dict(
                "role" => "user", 
                "content" => full_query
            )
        ]
        body = JSON.json(generator.body_dict)
        response = HTTP.request("POST", generator.url, generator.header, body)
    
        if response.status == 200
            response_str = String(response.body)
            parsed_dict = JSON.parse(response_str)
            result = parsed_dict["choices"][1]["message"]["content"]
        else
            error("Request failed with status code $(response.status): $(String(response.body))")
        end
    else
        # if we have time, we can use this to generate via something locally-hosted
        throw(ArgumentError("generator is not of a supported type."))
    end

    return result
end

"""
    function generate_with_corpus(generator::Union{OAIGenerator, Nothing}, corpus::Corpus, query::String, k::Int=5, temperature::Float64=0.7)

Parameters
----------
generator : Union{OAIGenerator, Nothing}
    an initialized generator (e..g OAIGenerator)
    leaving this as a union with nothing to note that we may want to support other 
    generator types in the future (e.g. HFGenerator, etc.)
corpus : an initialized Corpus object
    the corpus / "vector database" you want to use
query : String
    the main instruction or query string. This is basically your question
k : int
    The number of nearest-neighbor vectors to fetch from the corpus to build your context
temperature : Float64
    controls the stochasticity of the output generated by the model
"""
function generate_with_corpus(generator::Union{OAIGenerator, Nothing}, corpus::Corpus, query::String, k::Int=5, temperature::Float64=0.7)
    # search corpus
    idx_list, doc_names, chunks, distances = search(corpus, query, k)

    # generate as usual, but with chunks for context
    result = generate(generator, query, chunks, temperature)

    return result
end


end