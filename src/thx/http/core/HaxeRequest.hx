package thx.http.core;

import thx.Nil;
import haxe.Http;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import thx.http.*;
import thx.http.RequestType;
using thx.Arrays;
using thx.Functions;
using thx.Strings;
using thx.promise.Promise;

class HaxeRequest<T> extends Request<T> {
  public static function make<T>(requestInfo : RequestInfo, responseType : ResponseType<T>) : Request<T> {
    var request = new haxe.Http(requestInfo.url.toString());
    (requestInfo.headers : Array<Header>).each.fn(request.addHeader(_.key, _.value));

    function send() {
      switch requestInfo.method {
        case Get:   request.request(false);
        case Post:  request.request(true);
        case other: throw 'haxe.Http doesn\'t support method "$other"';
      }
    }
    var promiseBody = Promise.create(function(resolve : Dynamic -> Void, reject) {
      request.onData = function(d : String) {
        resolve(switch responseType {
          case Text:   d;
          case Binary: Bytes.ofString(d);
          case NoBody: Nil.nil;
          case Json:   haxe.Json.parse(d);
          case Input:
            var b = Bytes.ofString(d);
            new BytesInput(b);
        });
      };
    });

    var promise : Promise<Response<T>> = Promise.create(function(resolve : Response<T> -> Void, reject) {
          var completed = false;
          request.onStatus = function(s) {
            if(completed) return;
            completed = true;
            resolve(new HaxeResponse(s, promiseBody, request));
          };
          request.onError = function(msg) {
            // is onError firing twice?
            if(completed) {
              // forces completing the Respone Body promise
              request.onData(msg);
              request.onData = function(_){};
              return;
            }
            completed = true;
            reject(new HttpConnectionError(msg)); // TODO better error
          };
          switch requestInfo.body {
            case Text(s, _): // TODO encoding
              request.setPostData(s);
              send();
            case Binary(b):
              request.setPostData(b.toString());
              send();
            case Input(i):
              request.setPostData(i.readAll().toString());
              send();
            case NoBody: // do nothing
              send();
          }
        });
    return new HaxeRequest(promise, request);
  }

  public var request(default, null) : Http;
  function new(response : Promise<Response<T>>, request : Http) {
    this.response = response;
    this.request = request;
  }

  override function abort() {
#if(flash || js)
    request.cancel();
#else
    trace("haxe http doesn't support aborting requests on this platform");
#end
    return this;
  }
}

class HaxeResponse<T> extends thx.http.Response<T> {
  public var request(default, null) : Http;
  var _body : Promise<T>;
  var _status : Int;
  public function new(status : Int, body : Promise<T>, request : Http) {
    this._body = body;
    this._status = status;
    this.request = request;
  }

  override function get_body() return _body;
  override function get_statusCode() return _status;
  var _headers : Headers;
  override function get_headers() {
    if(null != _headers)
      return _headers;
    return _headers = request.responseHeaders;
  }
}
