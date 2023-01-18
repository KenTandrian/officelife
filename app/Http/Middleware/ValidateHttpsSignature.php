<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Support\Arr;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\App;
use Illuminate\Routing\Exceptions\InvalidSignatureException;

class ValidateHttpsSignature
{
    /**
     * The encryption key resolver callable.
     *
     * @var callable
     */
    public $keyResolver;

    /**
     * Set the encryption key resolver.
     */
    public function __construct()
    {
        $this->keyResolver = function () {
            return App::make('config')->get('app.key');
        };
    }

    /**
     * Based on vendor/laravel/framework/src/Illuminate/Routing/Middleware/ValidateSignature.php
     * but ensures that a url is always treated as https. This fixes the fact that
     * laravel running behind a rewrite proxy and getting urls as http.
     *
     * Handle an incoming request.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @return mixed
     */
    public function handle($request, Closure $next)
    {
        if ($this->hasValidSignature($request)) {
            return $next($request);
        }
        throw new InvalidSignatureException;
    }

    /**
     * Copied and modified from
     * vendor/laravel/framework/src/Illuminate/Routing/UrlGenerator.php:394.
     *
     * Determine if the given request has a valid signature.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  bool  $absolute
     * @return bool
     */
    public function hasValidSignature(Request $request, $absolute = true)
    {
        // $ignoreQuery removed on the next line
        return $this->hasCorrectSignature($request, $absolute)
            && $this->signatureHasNotExpired($request);
    }

    /**
     * Copied and modified from
     * vendor/laravel/framework/src/Illuminate/Routing/UrlGenerator.php:420.
     *
     * Determine if the signature from the given request matches the URL.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  bool  $absolute
     * @param  array  $ignoreQuery
     * @return bool
     */
    public function hasCorrectSignature(Request $request, $absolute = true, array $ignoreQuery = [])
    {
        $url = $absolute ? $request->url() : '/'.$request->path();

        // The Fix - Start
        $url = str_replace('http://', 'https://', $url);

        $original = rtrim($url.'?'.Arr::query(
            Arr::except($request->query(), 'signature')
        ), '?');
        // The Fix - End

        $signature = hash_hmac('sha256', $original, call_user_func($this->keyResolver));

        /** @psalm-suppress PossiblyInvalidCast */
        return hash_equals($signature, (string) $request->query('signature', ''));
    }

    /**
     * Copied and modified from
     * vendor/laravel/framework/src/Illuminate/Routing/UrlGenerator.php:443.
     *
     * Determine if the expires timestamp from the given request is not from the past.
     *
     * @param  \Illuminate\Http\Request  $request
     * @return bool
     */
    public function signatureHasNotExpired(Request $request)
    {
        $expires = $request->query('expires');

        /** @phpstan-ignore-next-line */
        return ! ($expires && Carbon::now()->getTimestamp() > $expires);
    }
}
