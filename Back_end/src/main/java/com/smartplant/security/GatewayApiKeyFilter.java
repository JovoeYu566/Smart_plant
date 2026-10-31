package com.smartplant.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import com.smartplant.config.SmartPlantProperties;

import java.io.IOException;
import java.util.List;

/**
 * 主节点 HTTP 上报：请求头 X-Gateway-Key 匹配配置则放行。
 */
@Component
@RequiredArgsConstructor
public class GatewayApiKeyFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Gateway-Key";

    private final SmartPlantProperties properties;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return !path.startsWith("/api/plant/report") || !"POST".equalsIgnoreCase(request.getMethod());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String key = request.getHeader(HEADER);
        String expected = properties.getGateway().getApiKey();
        if (StringUtils.hasText(key) && key.equals(expected)) {
            UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                    "gateway", null, List.of(new SimpleGrantedAuthority("ROLE_GATEWAY")));
            SecurityContextHolder.getContext().setAuthentication(auth);
        }
        filterChain.doFilter(request, response);
    }
}
